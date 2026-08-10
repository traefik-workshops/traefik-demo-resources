# =============================================================================
# compute/hyperv/vm — inputs
# =============================================================================
# The shared Hyper-V VM primitive that traefik/hyperv-vm (one gateway VM),
# apps/whoami/hyperv (N whoami VMs) and compute/hyperv/k3s (the hub VM)
# compose. Pure infra: it uploads the caller-rendered NoCloud seed files,
# builds the cidata ISO host-side, clones a differencing VHDX off the golden
# parent and boots the VM. It owns NO role config — user_data and
# network_config arrive as opaque per-instance strings, and traefik.* labels
# NEVER pass through here (they are VMM-side; see apps/whoami/hyperv).
# =============================================================================

variable "host_winrm" {
  description = "WinRM HTTPS access to the Hyper-V HOST the VMs are created on (the host has no API; every operation is a PowerShell one-shot over this listener). NTLM with a local or domain account that is a Hyper-V administrator. insecure defaults true — self-signed listeners are the lab norm."
  type = object({
    host     = string
    port     = optional(number, 5986)
    username = string
    password = string
    https    = optional(bool, true)
    insecure = optional(bool, true)
    use_ntlm = optional(bool, true)
    timeout  = optional(string, "10m")
  })
  sensitive = true
}

variable "switch_name" {
  description = "Name of the Hyper-V virtual switch each VM's NIC joins (the demo host preps an internal NAT switch; addressing is STATIC via each instance's network-config — there is no DHCP assumption)."
  type        = string
  default     = "traefik-lab"
}

variable "parent_vhdx_path" {
  description = "Host path of the READ-ONLY golden parent VHDX every VM's differencing disk chains to. Must be a generic Ubuntu CLOUD IMAGE converted qcow2->VHDX (NEVER the -azure.vhd artifact — it pins datasource_list to [Azure] and ignores NoCloud seeds) with linux-cloud-tools (the KVP daemon) baked in."
  type        = string
}

variable "workdir" {
  description = "Host directory the module works under: seed files + ISOs in <workdir>\\seeds\\<name>, differencing disks in <workdir>\\vms\\<name>."
  type        = string
  default     = "C:\\traefik-lab"
}

variable "num_cpus" {
  description = "vCPU count per VM (per-instance override via instances.*.num_cpus)"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB per VM (STATIC — dynamic memory is disabled so k3s/whoami sizing behaves; per-instance override via instances.*.memory)"
  type        = number
  default     = 4096
}

variable "generation" {
  description = "Hyper-V VM generation. 2 (the default) boots the Ubuntu cloud image via UEFI with Secure Boot on the Microsoft UEFI CA template; only change it for exotic guests."
  type        = number
  default     = 2
}

variable "instances" {
  description = "Map of VMs to create, keyed by VM name (also the guest hostname via the rendered meta-data). user_data / network_config are the already-rendered NoCloud payloads (opaque). ip_address is the PLAN-KNOWN guest address the network_config assigns (bare IP, no CIDR) — the module cannot parse it out of the opaque payload, so the caller states it once more and the outputs echo it; nothing here discovers addresses (see main.tf header)."
  type = map(object({
    user_data      = string
    network_config = string
    ip_address     = string
    memory         = optional(number)
    num_cpus       = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.instances : v.ip_address != ""])
    error_message = "Every instance needs its plan-known ip_address (the same address its network-config assigns)."
  }
}
