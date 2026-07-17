# =============================================================================
# compute/gcp/vm — the shared Google Compute Engine VM primitive
# =============================================================================
# Owns the google_compute_instance (and its optional firewall) that both
# traefik/gce and apps/whoami/gce used to declare inline. It knows NOTHING
# role-specific: the caller renders its own cloud-init, builds the `traefik`
# metadata / dashboard JSON, and hands the finished metadata + labels in per
# instance. The module just materializes the VM(s).
# =============================================================================

variable "instances" {
  description = <<-EOT
    Map of VM key -> per-instance config. The key becomes the VM `name`
    (callers use the "<app>-<replica>" scheme, e.g. "traefik-1", "whoami-1").
    - metadata:   the full GCE metadata map, already assembled by the caller
                  (includes the `user-data` cloud-init item and, on GCE, the
                  single `traefik` JSON workload item — metadata keys can't
                  contain dots, so provider labels ride inside that item).
    - labels:     dotless GCE labels (provider constraints only).
    - network_ip: fixed internal IP for the primary NIC (network_interface
                  .network_ip). Must sit in the instance's subnetwork range.
                  Empty = ephemeral/DHCP. Pinning makes a hub's uplink dial
                  address plan-known and stable across VM recreation.
  EOT
  type = map(object({
    metadata   = map(string)
    labels     = optional(map(string), {})
    network_ip = optional(string, "")
  }))
}

variable "machine_type" {
  description = "GCE machine type applied to every instance"
  type        = string
  default     = "e2-medium"
}

variable "zone" {
  description = "GCE zone the VMs are created in"
  type        = string
  default     = "us-central1-a"
}

variable "vm_image" {
  description = "Boot disk image (family or self link)"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_type" {
  description = "Boot disk type"
  type        = string
  default     = "pd-standard"
}

variable "network" {
  description = "VPC network the VMs join"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork the VMs join. Empty = let GCP pick the network's subnet in the zone's region (works on auto-mode networks like `default`)."
  type        = string
  default     = ""
}

variable "enable_public_ip" {
  description = "Attach an ephemeral public IP to each VM (adds an empty access_config block). Off by default — callers dial the private IP in-network."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Network tags applied to every VM (firewall targeting, dotless). The firewall rule name is derived from the first tag."
  type        = list(string)
  default     = []
}

variable "service_account" {
  description = "Optional attached service account (ADC identity). null = no service_account block on the VMs."
  type = object({
    email  = string
    scopes = list(string)
  })
  default = null
}

variable "enable_firewall" {
  description = "Create a firewall rule opening firewall_ports to the VMs from firewall_source_ranges (mirrors compute/azure/vnet's NSG idea — GCP firewalls are VPC-scoped, so the rule lives with the VMs it targets). Disable when the network already allows it (e.g. default network's default-allow-internal)."
  type        = bool
  default     = false
}

variable "firewall_ports" {
  description = "TCP ports (as strings) the firewall rule opens on the VMs."
  type        = list(string)
  default     = []
}

variable "firewall_source_ranges" {
  description = "Source CIDR ranges allowed by the firewall rule."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
