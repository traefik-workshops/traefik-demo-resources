variable "hostname" {
  type        = string
  description = "The name that must resolve before dependents may be created — in these demos, the OTLP collector's public host (collector.<domain>). This is the name every spoke dials, so it is the one whose absence gets negatively cached."
}

variable "upstream_id" {
  type        = string
  default     = ""
  description = "An id from whatever publishes the record (the hub Traefik / observability module). Threading it through the triggers re-gates when that is replaced, so rebuilt infrastructure cannot let spokes race a freshly-published name."
}

variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for public resolution before failing. Default 600s: dns-traefiker publishes within ~2.5 minutes of the LoadBalancer getting an address, so this is generous without masking a genuinely broken DNS controller. Failing here is far cheaper than the 1800s telemetry blackout it prevents."
}
