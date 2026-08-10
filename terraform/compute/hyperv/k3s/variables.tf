# --- Hyper-V placement (threaded to compute/hyperv/vm) -----------------------
variable "host_winrm" {
  description = "WinRM HTTPS access to the Hyper-V HOST the VM is created on (see compute/hyperv/vm)."
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
  type        = string
  description = "Hyper-V virtual switch the VM's NIC joins."
  default     = "traefik-lab"
}

variable "parent_vhdx_path" {
  type        = string
  description = "Golden parent VHDX the differencing disk chains to — a generic Ubuntu CLOUD IMAGE (never the -azure.vhd) with linux-cloud-tools baked in (see compute/hyperv/vm)."
}

variable "workdir" {
  type        = string
  description = "Host directory the VM's seed + differencing disk live under."
  default     = "C:\\traefik-lab"
}

# --- VM shape -----------------------------------------------------------------
variable "vm_name" {
  type        = string
  description = "Name for the k3s VM (also its hostname via the NoCloud meta-data, and the ambient kubeconfig context suffix k3s-<vm_name>)"
  default     = "k3s"
}

variable "num_cpus" {
  type        = number
  description = "vCPU count. The default fits a demo hub (Traefik Hub + Keycloak + a Grafana stack)."
  default     = 4
}

variable "memory" {
  type        = number
  description = "Memory in MB (static — the module disables dynamic memory)"
  default     = 8192
}

# --- Static addressing ---------------------------------------------------------
variable "ip_address" {
  type        = string
  description = "Static CIDR the node takes via the NoCloud network-config (e.g. 10.99.0.10/24). PLAN-KNOWN by design: it is also where klipper publishes LoadBalancer Services, so demo DNS wiring never waits on discovery."

  validation {
    condition     = can(cidrhost(var.ip_address, 0))
    error_message = "ip_address must be CIDR notation (e.g. 10.99.0.10/24)."
  }
}

variable "gateway" {
  type        = string
  description = "Default gateway for the node — the Hyper-V internal NAT switch's host-side address (e.g. 10.99.0.1)."
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the node. On the hyperv demo this is the lab router VM (dnsmasq: wildcard demo domain + public forwarding) — a static guest gets no DHCP, so forgetting this leaves the node unable to resolve anything."
  default     = []
}

# --- k3s ------------------------------------------------------------------------
variable "k3s_channel" {
  type        = string
  description = "k3s release channel for the install script (stable, latest, or a minor like v1.31)"
  default     = "stable"
}

variable "k3s_extra_args" {
  type        = list(string)
  description = "Extra `k3s server` arguments appended to the install. The module always sets --disable traefik (the traefik/k8s module deploys Hub instead) and --write-kubeconfig-mode 644 (the SSH kubeconfig fetch reads it without sudo); servicelb stays enabled so LoadBalancer Services get the node IP."
  default     = []
}

variable "tls_san" {
  type        = string
  description = "Extra Subject Alternative Name for the k3s serving cert (--tls-san). The node's own IP is a SAN by default, so this is only needed to reach the API by another name (a DNS alias, a VIP)."
  default     = ""
}

# --- SSH (kubeconfig retrieval) ---------------------------------------------------
variable "ssh_user" {
  type        = string
  description = "SSH user the kubeconfig fetch logs in as (the Ubuntu cloud image default user is `ubuntu`)"
  default     = "ubuntu"
}

variable "ssh_private_key" {
  type        = string
  description = "PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh_user — pass ssh_public_key so cloud-init authorizes it at first boot."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "Public key cloud-init authorizes for the image's default user at first boot. Empty = the golden image must already accept ssh_private_key."
  default     = ""
}

variable "kubeconfig_timeout" {
  type        = number
  description = "Seconds the kubeconfig fetch waits for k3s to finish installing on first boot"
  default     = 300
}

variable "update_kubeconfig" {
  type        = bool
  default     = true
  description = "Merge this cluster into the ambient kubeconfig (~/.kube/config, context k3s-<vm_name>) after creation and switch the current context to it — the on-prem analogue of the cloud modules' `update_kubeconfig`."
}
