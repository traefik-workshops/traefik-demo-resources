variable "apps" {
  description = "Map of applications to deploy to GCE VMs. Each app can have multiple replicas. Same shape as apps/whoami/ec2 EXCEPT the workload config: `traefik_labels` is a map of dotted Traefik label -> value, JSON-encoded into the single `traefik` metadata item (GCE metadata keys can't contain dots); optional `labels` are plain (dotless) GCE labels for provider constraints only. { name = { replicas, port, name, traefik_labels, labels } }."
  type        = any
  default     = {}
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
  description = "Common GCE labels to apply to all VMs (dotless — provider constraints only, not traefik.* config)"
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "Network tags applied to the VMs (firewall targeting). The firewall rule name is derived from the first tag."
  type        = list(string)
  default     = ["whoami"]
}

variable "whoami_version" {
  description = "The Whoami version to install. Must be a real traefik/whoami image tag — they carry a `v` prefix (e.g. v1.11.0); a bare `1.11.0` is `manifest unknown` and the binary extraction silently fails."
  type        = string
  default     = "v1.11.0"
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
