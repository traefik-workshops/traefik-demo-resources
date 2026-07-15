# =============================================================================
# Proxmox VE LXC Traefik Deployment — a multicluster CHILD gateway in a container
# =============================================================================
# The LXC sibling of traefik/proxmox-vm. Same shared config (traefik/shared via Helm
# template), same Hub, same :9443 uplink — but it runs INSIDE an LXC container, so the
# demo has one gateway per compute type (traefik-vm fronts the QEMU VMs, traefik-lxc
# fronts the LXC containers), the way aws pairs traefik-ec2/traefik-ecs and azure pairs
# traefik-vm/traefik-aci.
#
# TWO DELIBERATE DIFFERENCES FROM proxmox-vm:
#
# 1. NO cloud-init. A container has no user-data channel, so the config is delivered the
#    way apps/whoami/proxmox delivers its own: `pct push` + `pct exec` over SSH to the
#    node. The systemd unit here mirrors traefik/cloud-init's non-preview path — that
#    path already runs the Hub as a RAW BINARY under systemd, which is exactly what a
#    container wants.
#
# 2. SAME discovery plugin, DIFFERENT routes. This gateway runs the NX211 plugin exactly
#    like the VM child, so it discovers every labelled guest on the node — the plugin has
#    no node/type/tag filter and cannot be scoped, so BOTH children inevitably see BOTH
#    compute types. That is fine and expected. The separation is not enforced at
#    discovery; it is enforced by what each child ROUTES: this gateway's
#    file_provider_config only ever advertises the LXC services (lxc-whoami@plugin-proxmox),
#    and the VM child's only ever advertises the VM ones. Discovered-but-unrouted guests
#    just sit there (the plugin also mints a useless auto-router per guest, rule
#    Host(`<guest-name>`), which nothing resolves — harmless).
#
# The Hub binary comes from the same image the rest of the mesh runs (custom_image_*),
# extracted with crane. The demo runs a pre-release build that ships only as an image,
# and a child on a different Hub version cannot join the mesh — so pulling the released
# tarball instead is NOT equivalent.
#
# The container itself DOES need a static address (var.ip_address): the hub dials this
# child's :9443 uplink from its terraform-configured `children` map, and a container
# reports no DHCP lease back to terraform (no guest agent). That is the one thing the
# plugin cannot solve — it discovers backends, not the hub's view of its children.
# =============================================================================

locals {
  # The plugin's static config as CLI flags — identical delivery to traefik/proxmox-vm.
  # Its services surface as <name>@plugin-proxmox, which file_provider_config references.
  proxmox_plugin_args = var.proxmox_plugin.enabled ? concat(
    [
      "--experimental.plugins.proxmox.moduleName=github.com/NX211/traefik-proxmox-provider",
      "--experimental.plugins.proxmox.version=${var.proxmox_plugin.version}",
      "--providers.plugin.proxmox.pollInterval=${var.proxmox_plugin.poll_interval}",
      "--providers.plugin.proxmox.apiEndpoint=${var.proxmox_plugin.api_endpoint}",
      "--providers.plugin.proxmox.apiTokenId=${var.proxmox_plugin.api_token_id}",
      "--providers.plugin.proxmox.apiToken=${var.proxmox_api_token}",
      "--providers.plugin.proxmox.apiValidateSSL=${var.proxmox_plugin.api_validate_ssl}",
    ],
    var.proxmox_plugin.api_logging != "" ? ["--providers.plugin.proxmox.apiLogging=${var.proxmox_plugin.api_logging}"] : [],
  ) : []
}

module "config" {
  source = "../shared"

  # Extract CLI args + env from the Helm template, exactly like proxmox-vm/ec2/vsphere.
  extract_config = true

  # Feature Flags
  enable_api_gateway    = var.enable_api_gateway
  enable_ai_gateway     = var.enable_ai_gateway
  enable_mcp_gateway    = var.enable_mcp_gateway
  enable_api_management = false # K8s only
  enable_offline_mode   = var.enable_offline_mode
  enable_preview_mode   = false # never docker-in-LXC: the binary is extracted instead
  enable_debug          = var.enable_debug

  # Versions & Images
  traefik_chart_version   = var.traefik_chart_version
  traefik_tag             = var.traefik_tag
  traefik_hub_tag         = var.traefik_hub_tag
  traefik_hub_preview_tag = var.traefik_hub_preview_tag
  custom_image_registry   = var.custom_image_registry
  custom_image_repository = var.custom_image_repository
  custom_image_tag        = var.custom_image_tag

  # Observability
  log_level                    = var.log_level
  otlp_address                 = var.otlp_address
  otlp_service_name            = var.otlp_service_name
  enable_otlp_access_logs      = var.enable_otlp_access_logs
  enable_otlp_application_logs = var.enable_otlp_application_logs
  enable_otlp_metrics          = var.enable_otlp_metrics
  enable_otlp_traces           = var.enable_otlp_traces
  enable_prometheus            = var.enable_prometheus
  enable_access_logs           = var.enable_access_logs

  # Plugins & Extensions — the proxmox plugin rides here, same as the VM child.
  custom_plugins       = var.custom_plugins
  custom_ports         = var.custom_ports
  custom_arguments     = concat(var.custom_arguments, local.proxmox_plugin_args)
  custom_envs          = var.custom_envs
  file_provider_config = var.file_provider_config
  file_provider_path   = var.file_provider_path

  # Licensing
  traefik_hub_token = var.traefik_hub_token

  # Dashboard
  enable_dashboard      = var.enable_dashboard
  dashboard_insecure    = var.dashboard_insecure
  dashboard_entrypoints = var.dashboard_entrypoints
  dashboard_match_rule  = var.dashboard_match_rule

  # Providers
  multicluster_provider = var.multicluster_provider
}

locals {
  # extracted_cli_args_cloud already drops --hub.token (shared/outputs.tf); the unit
  # injects it from the env file so the token never lands in the process args.
  cli_arguments = module.config.extracted_cli_args_cloud

  env_vars_list = concat(
    module.config.env_vars_list,
    module.config.traefik_hub_token != "" ? [{ name = "HUB_TOKEN", value = module.config.traefik_hub_token }] : []
  )

  # /etc/traefik-hub/env — 0600, root-only: it carries the Hub license token.
  env_file = join("\n", [for e in local.env_vars_list : "${e.name}=${e.value}"])

  # Mirrors traefik/cloud-init's non-preview systemd unit. $${HUB_TOKEN} stays literal so
  # systemd expands it from EnvironmentFile at start.
  unit = <<-EOT
    [Unit]
    Description=Traefik Hub (proxmox LXC child gateway)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    EnvironmentFile=-/etc/traefik-hub/env
    ExecStart=/usr/local/bin/traefik-hub --hub.token=$${HUB_TOKEN} ${join(" ", local.cli_arguments)}
    Restart=always
    RestartSec=10
    LimitNOFILE=500000

    [Install]
    WantedBy=multi-user.target
  EOT

  setup = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # Gate on apt being USABLE, not merely on DNS resolving: a fresh container boots while
    # the host's DHCP/lab-DNS/NAT are still converging, so a name can resolve seconds
    # before apt can actually fetch. FAIL LOUD — a silent no-op here would leave the
    # gateway un-provisioned behind a green apply, which is exactly how the whoami LXC
    # went unnoticed for a whole validation round.
    apt_ready=0
    for i in $(seq 1 60); do if apt-get update -qq 2>/dev/null; then apt_ready=1; break; fi; echo "waiting for apt ($i/60)"; sleep 5; done
    [ "$apt_ready" = 1 ] || { echo "FATAL: apt never became usable in the container" >&2; exit 1; }
    apt-get install -y -qq curl ca-certificates tar

    # The Hub ships as an OCI image; crane pulls the binary out of it without a docker
    # daemon (nesting/overlayfs in an unprivileged container is not worth the fight).
    dl=0
    for i in $(seq 1 10); do if curl -fsSL --max-time 90 "https://github.com/google/go-containerregistry/releases/download/${var.crane_version}/go-containerregistry_Linux_x86_64.tar.gz" -o /tmp/gcr.tgz; then dl=1; break; fi; echo "retry crane download ($i/10)"; sleep 5; done
    [ "$dl" = 1 ] || { echo "FATAL: could not download crane" >&2; exit 1; }
    tar -xzf /tmp/gcr.tgz -C /usr/local/bin crane
    chmod +x /usr/local/bin/crane

    # Export the flattened rootfs to a FILE then extract: piping crane's stdout into
    # `tar -xO` is unreliable (GNU tar needs an explicit `-f -` for stdin). crane exports
    # linux/amd64 by default; the Hub image's entrypoint binary sits at the archive root.
    ex=0
    for i in $(seq 1 10); do if /usr/local/bin/crane export "${module.config.image_full}" /tmp/hub-rootfs.tar 2>/dev/null && tar -xf /tmp/hub-rootfs.tar -C /usr/local/bin traefik-hub 2>/dev/null && [ -s /usr/local/bin/traefik-hub ]; then ex=1; break; fi; echo "retry crane export ($i/10)"; sleep 5; done
    [ "$ex" = 1 ] || { echo "FATAL: could not extract /traefik-hub from ${module.config.image_full}" >&2; exit 1; }
    chmod +x /usr/local/bin/traefik-hub
    rm -f /tmp/hub-rootfs.tar /tmp/gcr.tgz

    mkdir -p /etc/traefik-hub/dynamic /data
    umask 077
    echo "${base64encode(local.env_file)}" | base64 -d >/etc/traefik-hub/env
    chmod 600 /etc/traefik-hub/env
    echo "${base64encode(var.file_provider_config)}" | base64 -d >/etc/traefik-hub/dynamic/dynamic.yaml
    chmod 644 /etc/traefik-hub/dynamic/dynamic.yaml
    echo "${base64encode(local.unit)}" | base64 -d >/etc/systemd/system/traefik-hub.service

    systemctl daemon-reload
    systemctl enable traefik-hub
    # restart, not `enable --now`: on a re-provision the unit is already running and
    # --now would not reload it, leaving the OLD binary and config live.
    systemctl restart traefik-hub
    echo "traefik-hub LXC provisioning complete"
  EOT
}

resource "proxmox_virtual_environment_container" "traefik" {
  node_name = var.node_name

  # No traefik.enable label: this gateway must not discover ITSELF as a backend. Its
  # dashboard is advertised over the uplink instead (a file rule), like the VM child's.
  description = "Traefik Hub — the LXC child gateway (${var.otlp_service_name}). Runs the NX211 plugin (which sees every guest — it cannot be scoped) but only ROUTES the LXC services; the VM child routes the VM ones."

  unprivileged = true

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = "debian"
  }

  cpu {
    cores = var.num_cpus
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  initialization {
    hostname = var.container_name

    ip_config {
      ipv4 {
        # STATIC, always: the hub dials https://<this address>:9443 for the uplink, so the
        # address has to be known at plan time. A container reports no DHCP lease back to
        # terraform (no guest agent), so DHCP here would leave the hub with nothing to dial.
        address = var.ip_address
        gateway = var.gateway
      }
    }

    # REQUIRED because the address above is static. A DHCP guest is handed the lab's
    # resolver in its lease (dnsmasq on the bridge, which answers *.<domain> with the
    # INTERNAL k3s address). Going static opts out of DHCP entirely — and therefore out of
    # lab DNS — so the container silently inherits the PVE host's PUBLIC resolvers. It then
    # resolves collector.<domain> through dns-traefiker to the box's PUBLIC ip and hairpins
    # back at the host, which refuses: the gateway serves traffic fine but ships NO
    # telemetry, and simply never appears in the service graph. Point it at the lab
    # resolver explicitly.
    dns {
      servers = length(var.dns_servers) > 0 ? var.dns_servers : [var.gateway]
      domain  = var.dns_search_domain != "" ? var.dns_search_domain : null
    }
  }

  features {
    nesting = true # systemd inside an unprivileged container
  }

  started = true

  lifecycle {
    precondition {
      condition     = var.lxc_template_file_id != ""
      error_message = "lxc_template_file_id is required."
    }
    precondition {
      condition     = var.ip_address != "" && var.gateway != ""
      error_message = "ip_address (CIDR) and gateway are required — the hub must dial this gateway's uplink at a known address."
    }
  }
}

# Install + configure the Hub inside the container. Pure terraform cannot provision inside
# an LXC (no cloud-init user-data path), so this SSHes to the PROXMOX NODE and
# `pct push` + `pct exec`s the setup script — the same node access the bpg provider's
# snippet upload already needs.
resource "terraform_data" "provision" {
  # Re-provision when the container is recreated or anything in the rendered config moves
  # (binary, CLI args, env, file provider, unit).
  triggers_replace = [
    proxmox_virtual_environment_container.traefik.id,
    sha1(local.setup),
  ]

  connection {
    type        = "ssh"
    host        = var.node_ssh.host
    user        = var.node_ssh.user
    private_key = var.node_ssh.private_key
  }

  provisioner "file" {
    content     = local.setup
    destination = "/tmp/traefik-lxc-setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      # pct is a root tool in /usr/sbin, which is NOT on the non-root SSH user's PATH, so
      # elevate. `set -e` so a pct failure fails the apply instead of a trailing command
      # masking it with exit 0 (a green apply that provisioned nothing).
      "set -e",
      "sudo pct push ${proxmox_virtual_environment_container.traefik.id} /tmp/traefik-lxc-setup.sh /tmp/traefik-lxc-setup.sh",
      "sudo pct exec ${proxmox_virtual_environment_container.traefik.id} -- bash /tmp/traefik-lxc-setup.sh",
      "rm -f /tmp/traefik-lxc-setup.sh",
    ]
  }

  lifecycle {
    precondition {
      condition     = var.node_ssh != null
      error_message = "node_ssh (SSH access to the Proxmox node) is required — the Hub is installed via pct exec."
    }
  }
}
