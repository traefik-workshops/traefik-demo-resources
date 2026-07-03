# --- vSphere placement ----------------------------------------------------
variable "datacenter" {
  type        = string
  description = "Name of the vSphere datacenter the VM is created in"
}

variable "datastore" {
  type        = string
  description = "Name of the datastore backing the VM's disk"
}

variable "cluster" {
  type        = string
  description = "Name of the compute cluster to place the VM in (its root resource pool). Provide this OR resource_pool."
  default     = ""

  validation {
    condition     = var.cluster != "" || var.resource_pool != ""
    error_message = "Provide cluster or resource_pool."
  }
}

variable "resource_pool" {
  type        = string
  description = "Name/path of the resource pool to place the VM in (e.g. \"Cluster/Resources/demo\"). Takes precedence over cluster."
  default     = ""
}

variable "network" {
  type        = string
  description = "Name of the port group / network the VM's NIC joins (DHCP is assumed)"
}

variable "template" {
  type        = string
  description = "Name of the VM template to clone. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (e.g. imported from ubuntu-24.04-server-cloudimg-amd64.ova) — a plain installer-built template ignores the guestinfo userdata and nothing boots k3s."
}

variable "folder" {
  type        = string
  description = "VM folder to place the VM in. Empty = the datacenter root."
  default     = ""
}

# --- VM shape ---------------------------------------------------------------
variable "vm_name" {
  type        = string
  description = "Name for the k3s VM (also its hostname)"
  default     = "k3s"
}

variable "num_cpus" {
  type        = number
  description = "vCPU count. The default fits a demo hub (Traefik Hub + Keycloak + a Grafana stack)."
  default     = 4
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 8192
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB. Grown to at least the template's disk (vSphere can't shrink on clone)."
  default     = 40
}

# --- k3s --------------------------------------------------------------------
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

# --- SSH (kubeconfig retrieval) ----------------------------------------------
variable "ssh_user" {
  type        = string
  description = "SSH user the kubeconfig fetch logs in as (the Ubuntu cloud image default user is `ubuntu`)"
  default     = "ubuntu"
}

variable "ssh_private_key" {
  type        = string
  description = "PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh_user — bake it into the template or pass ssh_public_key."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "Public key cloud-init authorizes for the template's default user at first boot. Empty = the template must already accept ssh_private_key."
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
