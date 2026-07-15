# Template-only module: the cloud-init payload is rendered in outputs.tf from cloud-init.tpl.

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # WHOAMI_NAME rides the same env pathway as caller-provided vars; caller env
  # wins on collision so `environment` can override the name if it wants to.
  environment = merge(
    var.name != "" ? { WHOAMI_NAME = var.name } : {},
    var.environment,
  )

  # The collector to gate the container start on — read straight off the env the
  # caller already sets, so no caller has to pass it twice. Empty when the caller
  # ships no telemetry, which skips the gate entirely.
  otlp_address = lookup(local.environment, "OTEL_EXPORTER_OTLP_ENDPOINT", "")
}
