output "rendered" {
  description = "Rendered."
  value = templatefile("${path.module}/cloud-init.tpl", {
    image        = local.image
    arch         = var.arch
    port         = var.port
    environment  = local.environment
    otlp_address = local.otlp_address
    # Shared cloud-init snippets (see terraform/cloud-init-snippets/README.md).
    docker_install = file("${path.module}/../../../cloud-init-snippets/docker-install.sh.tpl")
    collector_gate = local.otlp_address != "" ? templatefile("${path.module}/../../../cloud-init-snippets/otlp-collector-gate.sh.tpl", { otlp_address = local.otlp_address }) : ""
  })
}
