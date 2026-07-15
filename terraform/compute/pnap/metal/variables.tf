variable "hostname" {
  type        = string
  description = "Server hostname (also the BMC display name)."
}

variable "description" {
  type        = string
  description = "Free-text description shown in the BMC portal."
  default     = "traefik-demo private-cloud host"
}

variable "os" {
  type        = string
  description = "BMC OS image. The three the private-cloud demos use: proxmox/proxmox9 (Proxmox demo), esxi/esxi80 (vSphere demo — 60-day eval, deploy VCSA on top), ubuntu/noble (Morpheus demo — install the hpe-vm stack). Full list: the ServerCreate model in the BMC API docs. Changing it replaces the server."
  default     = "proxmox/proxmox9"
}

variable "type" {
  type        = string
  description = "BMC instance type (e.g. d3.c2.medium, s5.x6.c8.large — see phoenixnap.com/bare-metal-cloud/instances). Pick a virtualization-worthy size: the ESXi round wants >=128 GB RAM for VCSA + guests; the Proxmox/Morpheus rounds run comfortably on 64 GB. Cannot be changed after creation."
}

variable "location" {
  type        = string
  description = "BMC location ID (PHX, ASH, SGP, NLD, CHI, SEA, AUS)."
  default     = "PHX"
}

variable "ssh_keys" {
  type        = list(string)
  description = "SSH public keys installed on the server — the day-one access for the Linux images (proxmox/ubuntu). The ESXi image ignores these; use the generated root password output instead."
  default     = []
}

variable "install_default_ssh_keys" {
  type        = bool
  description = "Also install the account's default SSH keys."
  default     = true
}

variable "management_access_allowed_ips" {
  type        = list(string)
  description = "IPs/CIDRs allowed to reach the server's management UI, scoped at the phoenixNAP network layer (single IP, CIDR, or range). For the proxmox/proxmox9 image this is the Proxmox web UI on :8006; the BMC portal calls it 'White Listed IPs'. Empty (default) means BMC ships the image locked down (Proxmox: :8006 firewalled to SSH-only) — set it to the operator's IP so the demo's terraform can reach the API. PROVISION-TIME ONLY: the provider has no in-place update path, so a diff would re-image the server. main.tf therefore pins it with `ignore_changes`, so the whitelist is fixed at CREATE and later drift (a VPN, a new DHCP lease, applying from another network) can NEVER silently destroy the box. To re-scope it, change the value and `-replace` the server deliberately."
  default     = []
}

variable "pricing_model" {
  type        = string
  description = "Billing model. HOURLY is the point of this module — provision per demo, destroy after, pay for the window. Reservations only for a long-lived box."
  default     = "HOURLY"

  validation {
    condition     = contains(["HOURLY", "ONE_MONTH_RESERVATION", "TWELVE_MONTHS_RESERVATION", "TWENTY_FOUR_MONTHS_RESERVATION", "THIRTY_SIX_MONTHS_RESERVATION"], var.pricing_model)
    error_message = "pricing_model must be HOURLY or one of the *_RESERVATION values."
  }
}

variable "network_type" {
  type        = string
  description = "BMC network wiring. PUBLIC_AND_PRIVATE (default) gives the host a public IP for operator access plus the private backend network the demo guests NAT out of."
  default     = "PUBLIC_AND_PRIVATE"

  validation {
    condition     = contains(["PUBLIC_AND_PRIVATE", "PRIVATE_ONLY", "PUBLIC_ONLY", "USER_DEFINED"], var.network_type)
    error_message = "network_type must be PUBLIC_AND_PRIVATE, PRIVATE_ONLY, PUBLIC_ONLY or USER_DEFINED."
  }
}
