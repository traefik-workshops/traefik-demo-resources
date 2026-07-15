output "rendered" {
  description = "Rendered."
  value = templatefile("${path.module}/cloud-init.tpl", {
    image        = local.image
    arch         = var.arch
    port         = var.port
    environment  = local.environment
    otlp_address = local.otlp_address
  })
}
