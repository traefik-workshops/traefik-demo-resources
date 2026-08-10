variable "apps" {
  description = "Map of applications to deploy to GCE VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2 EXCEPT the workload config: instead of dotted traefik.* tags, an app's `labels` map carries plain GCE labels — including the service-name label the Hub gce provider reads (e.g. `traefik-service = \"whoami\"`), whose value names the ONE service the app's VMs back. Routing intent lives in the gateway's base configuration, never here. { name = { replicas, port, name, environment, labels } } — optional `environment` (map) is merged over the module-level `environment` into the container."
  type        = any
  default     = {}

  # GCE rejects invalid label values with an opaque API error at apply time;
  # worse, a syntactically valid but WRONG value (uppercase gets caught, but a
  # forgotten rename does not) silently detaches the VM from its service — the
  # provider skips unlabeled/mismatched instances with no error anywhere. Catch
  # the syntactic half at plan time.
  validation {
    condition = alltrue([
      for app in values(var.apps) : alltrue([
        for k, v in try(app.labels, {}) : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
      ])
    ])
    error_message = "GCE labels must be lowercase [a-z0-9_-] (keys start with a letter, 63 chars max). The service-name label's value is a service name in the gateway's base configuration — it cannot carry dots, commas, or routing syntax."
  }
}

variable "zone" {
  description = "GCE zone the VMs are created in"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "GCE machine type for all echo servers"
  type        = string
  default     = "e2-micro"
}

variable "vm_image" {
  description = "Boot disk image (family or self link)"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "network" {
  description = "VPC network the VMs join. Defaults to the project's default network — the same one compute/gcp/gke clusters sit on (see its `network` output), so the Traefik child reaches these VMs privately."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork the VMs join. Empty = let GCP pick the network's subnet in the zone's region (works on auto-mode networks like `default`)."
  type        = string
  default     = ""
}

variable "common_labels" {
  description = "Common GCE labels to apply to all VMs. Per-app `labels` win on collision; keep the service-name label per-app so each app names its own service."
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "Network tags applied to the VMs (firewall targeting). The firewall rule name is derived from the first tag."
  type        = list(string)
  default     = ["whoami"]
}

variable "whoami_image" {
  description = "Whoami image to docker-run on each VM. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami container (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "enable_public_ip" {
  description = "Attach an ephemeral public IP to each VM. Off by default — the Traefik child dials private IPs (ipMode=private)."
  type        = bool
  default     = false
}

variable "enable_firewall" {
  description = "Create a firewall rule opening the app ports intra-network to these VMs (mirrors compute/azure/vnet's NSG). Disable when the network already allows it (e.g. default network's default-allow-internal)."
  type        = bool
  default     = true
}

variable "firewall_source_ranges" {
  description = "Source CIDR ranges allowed by the firewall rule. Default covers the default network (10.128.0.0/9) and typical GKE node/pod ranges."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
