variable "resource_group_name" {
  type        = string
  description = "Resource group to create the recording workstation in."
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "eastus"
}

variable "vm_name" {
  type        = string
  description = "Base name for the VM, NIC, public IP, and NSG."
  default     = "demo-desktop"
}

variable "vm_size" {
  type        = string
  description = "VM size. Default is 4 vCPU / 16 GB (D-series, not burstable B — B stutters on screen capture)."
  default     = "Standard_D4s_v5"
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB."
  default     = 100
}

variable "os_disk_type" {
  type        = string
  description = "OS disk storage account type. Premium for smooth capture I/O."
  default     = "Premium_LRS"
}

variable "subnet_id" {
  type        = string
  description = "Subnet to attach the NIC to (e.g. compute/azure/vnet vm_subnet_id)."
}

variable "enable_public_ip" {
  type        = bool
  description = "Allocate a public IP so the operator can RDP/SSH in. Lock it down with source_address_prefix."
  default     = true
}

variable "enable_nsg" {
  type        = bool
  description = "Create a dedicated NSG allowing SSH + RDP from source_address_prefix and associate it to the NIC."
  default     = true
}

variable "source_address_prefix" {
  type        = string
  description = "CIDR/IP allowed to reach SSH (22) + RDP (3389). STRONGLY recommend your operator IP, not '*'."
  default     = "*"
}

variable "admin_username" {
  type        = string
  description = "Admin/login user (matches the hand-built workstation)."
  default     = "traefik"
}

variable "admin_password" {
  type        = string
  description = "Admin password (demo-grade; used for SSH + RDP + sudo). Set to a strong value."
  sensitive   = true
}

variable "rdp_resolution" {
  type        = string
  description = "Pinned desktop resolution for the dummy Xorg display ffmpeg captures."
  default     = "1920x1080"
}

variable "rdp_color_depth" {
  type        = number
  description = "Color depth for xrdp/Xorg (24 for clean capture)."
  default     = 24
}

variable "enable_recording_toolchain" {
  type        = bool
  description = "Install the recording stack (ffmpeg, wmctrl, xdotool, cursor-highlight) + the claude-in-chrome extension bootstrap."
  default     = true
}

variable "dev_toolchain" {
  description = "Per-tool install toggles. Default installs the full workstation toolchain."
  type = object({
    chrome         = optional(bool, true)
    vscode         = optional(bool, true)
    postman        = optional(bool, true)
    bruno          = optional(bool, true)
    claude_desktop = optional(bool, true)
    claude_code    = optional(bool, true)
    gh             = optional(bool, true)
    terraform      = optional(bool, true)
    az_cli         = optional(bool, true)
    gcloud         = optional(bool, true)
    aws_cli        = optional(bool, true)
    eksctl         = optional(bool, true)
    docker         = optional(bool, true)
    k3d            = optional(bool, true)
    helm           = optional(bool, true)
    kubectl        = optional(bool, true)
    kubectx        = optional(bool, true)
    krew           = optional(bool, true)
    k9s            = optional(bool, true)
  })
  default = {}
}

variable "git_deploy_key" {
  type        = string
  description = "Private SSH deploy key (RW) for the demo repo, written to ~/.ssh so git pull/push works headlessly. Empty = skip."
  default     = ""
  sensitive   = true
}

variable "git_repo_url" {
  type        = string
  description = "SSH URL of the demo repo to clone to ~/traefik-demo (used only when git_deploy_key is set)."
  default     = "git@github.com:traefik-workshops/traefik-demo.git"
}

variable "source_image_id" {
  type        = string
  description = "Optional Shared Image Gallery image id (Phase B golden image). Empty = vanilla Ubuntu 24.04 + cloud-init (Phase A)."
  default     = ""
}

variable "enable_reader_role" {
  type        = bool
  description = "Grant the VM identity Reader on the resource group (so `az login --identity` works read-only on the VM)."
  default     = true
}

variable "enable_contributor_role" {
  type        = bool
  description = "Grant Contributor instead of Reader (only if the desktop itself runs `make up` / provisions cloud infra)."
  default     = false
}

variable "extra_files" {
  description = "Extra files written by cloud-init (secrets, config) — { path, content, permissions }."
  type = list(object({
    path        = string
    content     = string
    permissions = optional(string, "0644")
  }))
  default = []
}

variable "extra_tags" {
  type        = map(string)
  description = "Extra tags to apply to the VM."
  default     = {}
}
