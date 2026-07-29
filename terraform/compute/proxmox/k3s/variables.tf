# --- Proxmox placement ------------------------------------------------------
variable "node_name" {
  type        = string
  description = "Name of the Proxmox VE node the VM is created on"
}

variable "datastore_id" {
  type        = string
  description = "Datastore backing the VM's disk and cloud-init drive (e.g. local-lvm). Must be the datastore the template's disk lives on, or the clone's disk is moved there."
}

variable "snippet_datastore_id" {
  type        = string
  description = "Datastore the cloud-init user-data snippet is uploaded to. Must have the Snippets content type enabled (the stock `local` does after enabling it in Datacenter > Storage)."
  default     = "local"
}

variable "bridge" {
  type        = string
  description = "Name of the Linux bridge the VM's NIC joins (DHCP is assumed)"
  default     = "vmbr0"
}

variable "template_vm_id" {
  type        = number
  description = "VMID of the template to clone. Provide this OR template_name. Must be a cloud-init-enabled Ubuntu CLOUD IMAGE template (imported cloud image + cloud-init drive) — a plain installer-built template ignores the user-data and nothing boots k3s."
  default     = 0
}

variable "template_name" {
  type        = string
  description = "Name of the template to clone (resolved to a VMID on the node). Takes precedence over template_vm_id."
  default     = ""

  validation {
    condition     = var.template_name != "" || var.template_vm_id != 0
    error_message = "Provide template_vm_id or template_name."
  }
}

# --- VM shape -----------------------------------------------------------------
variable "vm_name" {
  type        = string
  description = "Name for the k3s VM (also its hostname via the PVE-generated cloud-init meta-data)"
  default     = "k3s"
}

variable "num_cpus" {
  type        = number
  description = "vCPU count. The default fits a demo hub (Traefik Hub + Keycloak + a Grafana stack)."
  default     = 4
}

variable "cpu_type" {
  type        = string
  description = "QEMU CPU type. `host` passes the node's CPU through (fastest, lab-friendly); pick a named model (e.g. x86-64-v2-AES) when live migration matters."
  default     = "host"
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 8192
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB. Must be at least the template's disk (Proxmox can't shrink on clone)."
  default     = 40
}

variable "disk_interface" {
  type        = string
  description = "Interface of the template's disk to resize (the standard cloud-image import recipe attaches it as scsi0)"
  default     = "scsi0"
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
