#cloud-config

ssh_pwauth: true
users:
  - name: traefiker
    groups: sudo
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false

chpasswd:
  expire: false
  list: |
    traefiker:topsecretpassword

write_files:
  - path: /etc/systemd/system/whoami.service
    content: |
      [Unit]
      Description=Traefik Whoami Service
      After=network.target docker.service
      Requires=docker.service

      [Service]
      # A leftover container from a previous boot would collide on --name; the
      # `-` prefix makes the rm a no-op when nothing is there.
      ExecStartPre=-/usr/bin/docker rm -f whoami
      ExecStart=/usr/bin/docker run --rm --name whoami --platform linux/${arch} -p ${port}:80%{ for k, v in environment } -e "${k}=${v}"%{ endfor } ${image} --verbose
      ExecStop=/usr/bin/docker stop whoami
      Restart=always

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: "0644"

runcmd:
  # Install Docker based on distribution
  - |
    if command -v apt-get >/dev/null; then
      apt-get update -y
      apt-get install -y docker.io
      systemctl start docker
      systemctl enable docker
    elif command -v yum >/dev/null; then
      yum update -y
      yum install -y docker
      systemctl start docker
      systemctl enable docker
    fi

  # Wait for Docker to be ready, then pre-pull the whoami image as one fail-fast
  # block — a bad pull surfaces in `cloud-init status` instead of silently leaving
  # whoami.service crash-looping on the pull at start.
  - |
    # POSIX sh only: cloud-init runs runcmd with /bin/sh (dash on Ubuntu),
    # which rejects `set -o pipefail`. No pipelines here, so `set -eu` is enough.
    set -eu
    for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; echo "waiting for docker ($i)"; sleep 2; done
    echo "Pulling ${image} (linux/${arch})"
    # Retry the pull (~4 min): the instance can boot before its NAT gateway is ready
    # (private-subnet spokes), so an early pull failure usually just means egress isn't up.
    for i in $(seq 1 20); do
      docker pull --platform linux/${arch} ${image} && break
      echo "Retrying whoami image pull ($i/20)..."
      sleep 10
    done

%{ if otlp_address != "" ~}
  # Gate whoami on the collector endpoint actually accepting OTLP writes. The
  # whoami fork resolves OTEL_EXPORTER_OTLP_ENDPOINT once at start: first boot
  # races dns-traefiker publishing collector.<domain>, and an exporter that
  # starts against an unresolvable endpoint stays dark for the life of the
  # container — the backend then emits no spans, so the service map loses the
  # whole leg (`traefik-<type> -> unknown`) while every route still serves 200
  # (oci-unified-ingress validation, 2026-07). Skipped entirely when no OTLP
  # endpoint is configured. Bounded: 30 min, then start anyway.
  - |
    for i in $(seq 1 180); do
      curl -skf --max-time 5 -X POST -H 'Content-Type: application/json' \
        -d '{"resourceMetrics":[]}' "${otlp_address}/v1/metrics" > /dev/null && { echo "OTLP collector ready."; break; }
      echo "Waiting for OTLP collector ${otlp_address} ($i/180)..."
      sleep 10
    done
%{ endif ~}

  # Start Service
  - systemctl daemon-reload
  - systemctl enable --now whoami.service

  # Signal readiness
  - echo "Whoami provisioning complete"
