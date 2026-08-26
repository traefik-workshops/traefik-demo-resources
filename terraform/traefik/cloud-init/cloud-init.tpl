#cloud-config

%{ if data_disk != null ~}
# Extra block device, partitioned/formatted/mounted BEFORE anything installs.
#
# `disk_setup`, `fs_setup` and `mounts` are cloud-init INIT-stage modules, so they complete
# before `runcmd` (cloud-final) — which is the whole point. `extra_runcmd` cannot be used for
# this: it is appended AFTER the container-engine install and image pull further down, so a
# mount made there arrives too late to give them anywhere to write.
#
# Sized for guests whose root is a containerDisk: those are fixed at the image's virtual size
# (quay.io/containerdisks/ubuntu:24.04 is 3.5 GiB, of which the base already uses ~2.6 GiB),
# leaving under a gigabyte — not enough for dockerd plus a Hub image, and the failure is a
# bare "no space left on device" from containerd deep in a pull retry loop.
disk_setup:
  ${data_disk.device}:
    table_type: gpt
    layout: true
    overwrite: true
fs_setup:
  - label: data
    filesystem: ext4
    device: ${data_disk.device}
    partition: 1
    overwrite: true
mounts:
  - [ ${data_disk.device}1, ${data_disk.mount_path}, ext4, "defaults,nofail", "0", "2" ]
%{ endif ~}

ssh_pwauth: true

users:
  - name: traefiker
    groups: sudo
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false
%{ if ssh_public_key != "" ~}
    # Key auth alongside the demo password. Password-only was a genuine debugging tax:
    # diagnosing the vSphere JWT failure needed an `expect` script to drive the prompt,
    # and on Morpheus a REFUSED password was the only symptom of a child whose cloud-init
    # had never run -- indistinguishable from a wrong password until it was ruled out.
    # A key makes `ssh traefiker@<gw>` work from any script, and every caller already has
    # one for its k3s/whoami guests.
    ssh_authorized_keys:
      - "${ssh_public_key}"
%{ endif ~}

chpasswd:
  expire: false
  list:
    - traefiker:topsecretpassword

write_files:
  - path: /etc/ssh/sshd_config.d/99-traefik.conf
    owner: root:root
    permissions: "0644"
    content: |
      PasswordAuthentication yes

  - path: /etc/sysctl.d/99-traefik-perf.conf
    owner: root:root
    permissions: "0644"
    content: |
      net.ipv4.tcp_tw_reuse = ${performance_tuning.tcp_tw_reuse}
      net.ipv4.tcp_timestamps = ${performance_tuning.tcp_timestamps}
      net.core.rmem_max = ${performance_tuning.rmem_max}
      net.core.wmem_max = ${performance_tuning.wmem_max}
      net.core.somaxconn = ${performance_tuning.somaxconn}
      net.core.netdev_max_backlog = ${performance_tuning.netdev_max_backlog}
      net.ipv4.ip_local_port_range = ${performance_tuning.ip_local_port_range}

  - path: /etc/systemd/system/traefik-hub.service
    owner: root:root
    permissions: "0644"
    content: |
      [Unit]
      Description=Traefik Hub
      After=network-online.target
      Wants=network-online.target
%{ if dns_traefiker.enabled ~}
      After=dns-traefiker.service
      Wants=dns-traefiker.service
%{ endif ~}

      [Service]
      Type=simple
      EnvironmentFile=-/etc/traefik-hub/env
      EnvironmentFile=-/etc/traefik-hub/dns-traefiker.env
%{ if dns_traefiker.enabled ~}
      ExecStartPre=/bin/bash -c 'for i in $(seq 1 60); do grep -q CF_DNS_API_TOKEN /etc/traefik-hub/dns-traefiker.env && exit 0; sleep 5; done; echo "WARNING: CF token not found after 300s, starting anyway"; exit 0'
%{ endif ~}
      LimitNOFILE=${performance_tuning.limit_nofile}
      %{ if performance_tuning.gomaxprocs > 0 }
      Environment=GOMAXPROCS=${performance_tuning.gomaxprocs}
      %{ endif }
      Environment=GOGC=${performance_tuning.gogc}
      %{ if performance_tuning.numa_node >= 0 }
      NUMAPolicy=bind
      NUMAMask=${performance_tuning.numa_node}
      CPUAffinity=numa
      %{ endif }
%{ if enable_preview_mode ~}
      # Preview/dev builds (e.g. the EC2 and OCI cloud providers, not yet in a Hub release)
      # ship only as a container image, and a dev binary extracted from it isn't reliably
      # standalone. Run the image as a CONTAINER instead — --network host so the uplink :9443,
      # the local whoami, and the instance metadata service (IMDS, the provider's
      # instance/resource-principal credentials) all work, matching how the k8s spokes run the
      # same image. The mounted dynamic dir carries the file-provider config.
      # The Docker socket is bound in ONLY for a child whose discovery IS Docker
      # (--providers.docker). Preview mode runs Traefik as a container with just the two
      # binds above, so the provider would otherwise have no path to the daemon and would
      # publish nothing. Default off: mounting the socket is root-equivalent access to the
      # host, which no gateway that fronts anything real should have.
      ExecStartPre=-/usr/bin/docker rm -f traefik-hub
      ExecStartPre=/usr/bin/docker pull ${preview_image}
      ExecStart=/usr/bin/docker run --rm --name traefik-hub --network host --env-file /etc/traefik-hub/env -v /etc/traefik-hub/dynamic:/etc/traefik-hub/dynamic -v /data:/data%{ if mount_docker_socket } -v /var/run/docker.sock:/var/run/docker.sock%{ endif } ${preview_image} --hub.token=$${HUB_TOKEN} ${join(" ", [for a in cli_arguments : replace(a, "\\", "\\\\")])}
      ExecStop=-/usr/bin/docker stop traefik-hub
%{ else ~}
      ExecStart=/usr/local/bin/traefik-hub --hub.token=$${HUB_TOKEN} ${join(" ", [for a in cli_arguments : replace(a, "\\", "\\\\")])}
%{ endif ~}
      Restart=always
      RestartSec=10
      AmbientCapabilities=CAP_NET_BIND_SERVICE

      [Install]
      WantedBy=multi-user.target

%{ if anytrue([for a in cli_arguments : can(regex("uplinkEntryPoints", a))]) ~}
  # Self-heal for the Hub uplink-mixer boot race, written ONLY on a multicluster
  # child (one that exports an uplink entrypoint). The mixer assembles this child's
  # exported routers once at startup; if a discovery provider (vsphere, vmoperator,
  # ...) has not finished its first refresh yet, the mixer finds no child routers,
  # logs "no child routers could be added to mixer", and does NOT rebuild when
  # discovery later lands -- so the child exports nothing and the hub imports
  # nothing. This companion watches for that exact symptom and restarts the gateway
  # once discovery is up, so the mixer reassembles with the routers present.
  - path: /usr/local/bin/traefik-hub-mixerheal.sh
    owner: root:root
    permissions: "0755"
    content: |
      #!/bin/bash
      set -u
      MARK=/var/lib/traefik-hub-mixer-healed
      [ -f "$MARK" ] && exit 0

      # Read the gateway's own logs, whichever way it runs. A preview child runs the
      # image as the `traefik-hub` container (fresh logs per run, so a post-restart
      # check sees only the new container); a binary child logs to the journal.
      container_logs() {
        if command -v docker >/dev/null 2>&1 && docker inspect traefik-hub >/dev/null 2>&1; then
          docker logs traefik-hub 2>&1
        else
          journalctl -u traefik-hub --no-pager 2>/dev/null
        fi
      }
      mixer_starved() { container_logs | grep -q 'no child routers could be added to mixer'; }

      # Nothing to heal until the mixer actually reports starvation. Watch startup for
      # ~10 min; if the message never appears, this child raced nothing -- exit clean.
      starved=false
      for _ in $(seq 1 120); do
        if mixer_starved; then starved=true; break; fi
        sleep 5
      done
      if ! $starved; then touch "$MARK"; exit 0; fi

      # The mixer starved. Restart, each time first waiting long enough for the
      # discovery provider's next refresh to publish, then confirm the fresh container
      # no longer starves. Bounded to 3 attempts and marker-guarded: never a loop.
      for _ in 1 2 3; do
        sleep 30
        systemctl restart traefik-hub
        sleep 45
        mixer_starved || break
      done
      touch "$MARK"
  - path: /etc/systemd/system/traefik-hub-mixerheal.service
    owner: root:root
    permissions: "0644"
    content: |
      [Unit]
      Description=Traefik Hub uplink-mixer boot-race self-heal
      After=traefik-hub.service

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/usr/local/bin/traefik-hub-mixerheal.sh

      [Install]
      WantedBy=multi-user.target

%{ endif ~}
%{ if dns_traefiker.enabled }
  - path: /etc/systemd/system/dns-traefiker.service
    owner: root:root
    permissions: "0644"
    content: |
      [Unit]
      Description=DNS Traefiker
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      EnvironmentFile=/etc/traefik-hub/dns-traefiker.env
      Environment=ENV_FILE_PATH=/etc/traefik-hub/dns-traefiker.env
      ExecStart=/usr/local/bin/dns-traefiker
      Restart=always
      RestartSec=30

      [Install]
      WantedBy=multi-user.target

  - path: /etc/traefik-hub/dns-traefiker.env
    owner: root:root
    permissions: "0600"
    content: |
      DOMAIN=${dns_traefiker.domain}
      UNIQUE_DOMAIN=${dns_traefiker.unique_domain}
      PROXIED=${dns_traefiker.proxied}
      ENABLE_AIRLINES_SUBDOMAIN=${dns_traefiker.enable_airlines_subdomain}
      IP_OVERRIDE=${dns_traefiker.ip_override}
%{ endif }

  - path: /etc/systemd/system/node_exporter.service
    owner: root:root
    permissions: "0644"
    content: |
      [Unit]
      Description=Node Exporter
      After=network.target

      [Service]
      User=root
      ExecStart=/usr/local/bin/node_exporter --collector.cpu --collector.schedstat --collector.perf --web.listen-address=:9102
      Restart=always

      [Install]
      WantedBy=multi-user.target

  - path: /etc/traefik-hub/env
    owner: root:root
    permissions: "0600"
    content: |
      %{ for env in env_vars ~}
      ${env.name}=${env.value}
      %{ endfor ~}

%{ if file_provider_config != "" ~}
  - path: /etc/traefik-hub/dynamic/dynamic.yaml
    owner: root:root
    permissions: "0644"
    content: |
      ${indent(6, file_provider_config)}
%{ endif ~}

%{ for f in extra_files ~}
  - path: ${f.path}
    owner: root:root
    permissions: "0644"
    content: |
      ${indent(6, f.content)}
%{ endfor ~}

%{ if dashboard_config != "" ~}
  - path: /etc/traefik-hub/dynamic/dashboard.yaml
    owner: root:root
    permissions: "0644"
    content: |
      ${indent(6, dashboard_config)}
%{ endif ~}

%{ if vip != "" ~}
  - path: /etc/keepalived/keepalived.conf
    owner: root:root
    permissions: "0644"
    content: |
      vrrp_instance VI_1 {
        state BACKUP
        interface ${network_interface}
        virtual_router_id 51
        priority ${keepalived_priority}
        advert_int 1
        authentication {
          auth_type PASS
          auth_pass 1111
        }
        virtual_ipaddress {
          ${vip}
        }
      }
%{ endif ~}

runcmd:
  - sysctl -p /etc/sysctl.d/99-traefik-perf.conf
  - |
    # OCI's Ubuntu images ship a default iptables INPUT chain that ACCEPTs only SSH,
    # ICMP, loopback and established connections, then REJECTs everything else — so a
    # Traefik started with `--network host` (see the systemd unit above) is unreachable
    # on its entrypoints (:9443 multicluster uplink, :80/:443, :8080 api, :9100 metrics)
    # and on node_exporter (:9102), even though the OCI security list allows them. A
    # `docker -p` publish would add its own ACCEPT rules, but host networking does not,
    # so open the ports explicitly. No-op on AWS/Azure/GCP images (INPUT policy already
    # ACCEPT, no REJECT rule), which is why the sibling cloud spokes never needed it.
    if command -v iptables >/dev/null 2>&1; then
      iptables -I INPUT -p tcp -m multiport --dports 80,443,8080,9100,9102,9443 -j ACCEPT || true
      iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
  - mkdir -p /etc/traefik-hub/dynamic
  - mkdir -p /data
  - echo "{}" > /data/acme.json && chmod 600 /data/acme.json
  - chmod 666 /etc/traefik-hub/dns-traefiker.env
  - sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sysctl -w kernel.perf_event_paranoid=-1
  - echo "kernel.perf_event_paranoid = -1" > /etc/sysctl.d/99-perf.conf
  - systemctl restart ssh || systemctl restart sshd
  - |
    # Install Node Exporter v1.10.2
    if ! [ -f /usr/local/bin/node_exporter ]; then
      echo "Installing Node Exporter..."
      # Patient retry: first boot can race NAT-gateway/route readiness (observed:
      # 5 quick retries all burned inside the not-yet-routable window and host
      # metrics stayed dead for the VM's lifetime — aws-unified-ingress validation).
      for i in $(seq 1 30); do
        if curl -L --connect-timeout 10 --max-time 120 "https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz" -o /tmp/node_exporter.tar.gz; then
          mkdir -p /tmp/node_exporter-extract
          tar xvfz /tmp/node_exporter.tar.gz -C /tmp/node_exporter-extract
          BINARY=$(find /tmp/node_exporter-extract -type f -name "node_exporter" | head -n 1)
          if [ -n "$BINARY" ]; then
            mv "$BINARY" /usr/local/bin/node_exporter
            chmod +x /usr/local/bin/node_exporter
            echo "Node Exporter binary installed."
            break
          fi
        fi
        echo "Retrying Node Exporter download ($i/30)..."
        sleep 10
      done
      rm -rf /tmp/node_exporter-extract /tmp/node_exporter.tar.gz
    fi
    if [ -f /usr/local/bin/node_exporter ]; then
      systemctl daemon-reload
      systemctl enable node_exporter || true
      systemctl start node_exporter || true
    fi
%{ if enable_preview_mode ~}
  - |
    # Preview/dev image: install Docker + pull the image; traefik-hub.service runs it as a
    # container (see the unit above) — NO binary extraction. A dev binary run standalone on the
    # VM isn't reliable; the container carries its full runtime and (with --network host) reaches
    # the EC2 IMDS for the provider's instance-profile credentials.
    echo "Preview mode - installing Docker + pulling ${preview_image}..."
    # Shared snippet: terraform/cloud-init-snippets/docker-install.sh.tpl (rendered
    # by the caller and injected pre-rendered — templatefile has no include).
    ${indent(4, docker_install)}
    PREVIEW_IMAGE="${preview_image}"
    for i in $(seq 1 30); do
      docker pull "$PREVIEW_IMAGE" && break
      echo "Retrying preview image pull ($i/30)..."; sleep 10
    done
    if ! docker image inspect "$PREVIEW_IMAGE" >/dev/null 2>&1; then
      echo "ERROR: Failed to pull preview image $PREVIEW_IMAGE"; exit 1
    fi
%{ else ~}
  - |
    # Robust download and install
    ARCH="${arch}"
    VERSION="${traefik_hub_version}"
    case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
    DOWNLOAD_ARCH="amd64"
    case "$ARCH" in aarch64|arm64) DOWNLOAD_ARCH="arm64" ;; esac

    URL="https://github.com/traefik/hub/releases/download/$VERSION/traefik-hub_$${VERSION}_linux_$${DOWNLOAD_ARCH}.tar.gz"
    echo "Downloading Traefik Hub from $URL..."

    # Up to ~4 min of patience: an instance can boot before its NAT gateway is ready
    # (private-subnet spokes especially), so an early failure here usually just means
    # "egress not up yet" — keep retrying instead of giving up after ~75s.
    # --retry-connrefused covers transient connection refusals within each attempt.
    for i in $(seq 1 20); do
      if curl -fL --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 5 --retry-connrefused "$URL" -o /tmp/traefik-hub.tar.gz; then
        mkdir -p /tmp/traefik-hub-extract
        tar -xzf /tmp/traefik-hub.tar.gz -C /tmp/traefik-hub-extract
        BINARY=$(find /tmp/traefik-hub-extract -maxdepth 1 -type f -name "traefik-hub*" | head -n 1)
        if [ -n "$BINARY" ]; then
          mv "$BINARY" /usr/local/bin/traefik-hub
          chmod +x /usr/local/bin/traefik-hub
          echo "Traefik Hub binary installed."
          break
        fi
      fi
      echo "Retrying Traefik Hub download ($i/20)..."
      sleep 10
    done
    rm -rf /tmp/traefik-hub-extract /tmp/traefik-hub.tar.gz

    if [ ! -f /usr/local/bin/traefik-hub ]; then
      echo "ERROR: Failed to install Traefik Hub after retries"
      exit 1
    fi
%{ endif ~}

%{ if vip != "" ~}
  - |
    # Install Keepalived
    apt-get update && apt-get install -y keepalived
    systemctl enable --now keepalived
%{ endif ~}

  - systemctl daemon-reload
%{ if dns_traefiker.enabled ~}
  - |
    # Install dns-traefiker binary from GHCR
    if ! [ -f /usr/local/bin/dns-traefiker ]; then
      echo "Installing dns-traefiker from GHCR..."
      DOWNLOAD_ARCH="amd64"
      case "${arch}" in aarch64|arm64) DOWNLOAD_ARCH="arm64" ;; esac
      GHCR_REPO="traefik-workshops/dns-traefiker-bin"
      GHCR_TAG="${dns_traefiker.version}-linux-$DOWNLOAD_ARCH"

      for i in $(seq 1 5); do
        # Get anonymous pull token
        TOKEN=$(curl -sf "https://ghcr.io/token?scope=repository:$GHCR_REPO:pull" | \
          python3 -c "import sys,json;print(json.load(sys.stdin)['token'])" 2>/dev/null)
        if [ -z "$TOKEN" ]; then
          echo "Failed to get GHCR token (attempt $i/5)"
          sleep 5
          continue
        fi

        # Get manifest and extract binary layer digest
        DIGEST=$(curl -sf -H "Authorization: Bearer $TOKEN" \
          -H "Accept: application/vnd.oci.image.manifest.v1+json" \
          "https://ghcr.io/v2/$GHCR_REPO/manifests/$GHCR_TAG" | \
          python3 -c "import sys,json;print(json.load(sys.stdin)['layers'][0]['digest'])" 2>/dev/null)
        if [ -z "$DIGEST" ]; then
          echo "Failed to get manifest digest (attempt $i/5)"
          sleep 5
          continue
        fi

        # Download binary blob
        if curl -fL -H "Authorization: Bearer $TOKEN" \
          "https://ghcr.io/v2/$GHCR_REPO/blobs/$DIGEST" \
          -o /usr/local/bin/dns-traefiker; then
          chmod +x /usr/local/bin/dns-traefiker
          # Verify it's an actual binary
          if file /usr/local/bin/dns-traefiker | grep -q "ELF"; then
            echo "dns-traefiker binary installed successfully."
            break
          else
            echo "Downloaded file is not a valid ELF binary (attempt $i/5)"
            rm -f /usr/local/bin/dns-traefiker
          fi
        fi
        echo "Retrying dns-traefiker download ($i/5)..."
        sleep 5
      done
    fi
    if [ -f /usr/local/bin/dns-traefiker ]; then
      systemctl enable --now dns-traefiker
    else
      echo "WARNING: dns-traefiker binary not found, skipping service start"
    fi
%{ endif ~}
%{ if otlp_address != "" ~}
  - |
    # Shared snippet: terraform/cloud-init-snippets/otlp-collector-gate.sh.tpl.
    ${indent(4, collector_gate)}
    # Exhaustion is deliberately NOT fatal on a VM leg. cloud-init owns the rest of
    # this boot -- `systemctl enable --now traefik-hub` is still below - so a gate
    # that gives up must degrade this gateway to "starts, reports late", never to a
    # half-provisioned VM with no Traefik on it. That is why the snippet parks its
    # result in a variable rather than exiting: nothing reads $otlp_gate_status here
    # except the line below, which only makes the choice audible in the console log.
    #
    # The container legs invert exactly this - compute/aws/ecs turns the same
    # exhaustion into a failed task - because there "started anyway" means an
    # exporter dark for the life of the task, with no second boot to put it right.
    [ "$otlp_gate_status" -eq 0 ] || echo "otlp-gate: starting Traefik without a verified collector -- early telemetry from this host will be lost." >&2
%{ endif ~}
%{ for cmd in extra_runcmd ~}
  - |
    # Caller-supplied provisioning for workloads that must SHARE this VM's Docker daemon —
    # the docker-provider leg, whose containers only exist to be discovered through the
    # socket bound in above. Deliberately placed here: after the preview block has installed
    # Docker and pulled the gateway image, but BEFORE traefik-hub starts, so the provider's
    # very first refresh already sees the containers instead of publishing an empty service.
    ${indent(4, cmd)}
%{ endfor ~}
  - systemctl enable --now traefik-hub
%{ if anytrue([for a in cli_arguments : can(regex("uplinkEntryPoints", a))]) ~}
  # Multicluster child only: heals the uplink-mixer boot race (see the unit above).
  # Enabled without --now so its ~10 min watch runs in the background, not inline.
  - systemctl enable traefik-hub-mixerheal
  - systemctl start --no-block traefik-hub-mixerheal
%{ endif ~}
  - echo "Traefik Hub provisioning complete"
