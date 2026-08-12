output "rendered" {
  description = "Rendered."
  value = templatefile("${path.module}/cloud-init.tpl", {
    # Shared cloud-init snippets, rendered here and injected pre-rendered
    # (templatefile has no include; see terraform/cloud-init-snippets/README.md).
    docker_install       = file("${path.module}/../../cloud-init-snippets/docker-install.sh.tpl")
    collector_gate       = var.otlp_address != "" ? templatefile("${path.module}/../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = var.otlp_address, rounds = 180, verify_tls = false }) : ""
    traefik_hub_version  = var.traefik_hub_version
    arch                 = var.arch
    cli_arguments        = var.cli_arguments
    env_vars             = var.env_vars
    file_provider_config = var.file_provider_config
    extra_files          = var.extra_files
    mount_docker_socket  = var.mount_docker_socket
    ssh_public_key       = var.ssh_public_key
    extra_runcmd         = var.extra_runcmd
    data_disk            = var.data_disk
    dashboard_config     = var.dashboard_config
    performance_tuning   = var.performance_tuning
    vip                  = var.vip
    keepalived_priority  = var.keepalived_priority
    network_interface    = var.network_interface
    otlp_address         = var.otlp_address
    instance_name        = var.instance_name
    dns_traefiker        = var.dns_traefiker
    enable_preview_mode  = var.enable_preview_mode
    preview_image        = var.preview_image
  })
}
