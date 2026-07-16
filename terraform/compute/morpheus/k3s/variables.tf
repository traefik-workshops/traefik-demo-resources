# --- Morpheus placement -------------------------------------------------------
# Morpheus provisions from library concepts (cloud/group/instance type/layout/
# plan), all pre-existing on the appliance; this module looks them up by name.
variable "cloud" {
  type        = string
  description = "Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instance is provisioned into"
}

variable "group" {
  type        = string
  description = "Name of the Morpheus group the instance belongs to"
}

variable "instance_type" {
  type        = string
  description = "Name of the Morpheus instance type to provision from (e.g. \"Ubuntu\"). Must be an instance type whose layout boots a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) is what runs the k3s bootstrap."
  default     = "Ubuntu"
}

variable "instance_layout" {
  type        = string
  description = "Name of the instance layout under instance_type (e.g. \"Single KVM VM\")"
}

variable "instance_layout_version" {
  type        = string
  description = "Version of the instance layout (e.g. \"24.04\") — disambiguates layouts sharing a name. Empty = match by name alone."
  default     = ""
}

variable "plan" {
  type        = string
  description = "Name of the service plan — the plan IS the VM shape on Morpheus (no per-module cpu/memory knobs), so pick one that fits a demo hub (e.g. \"4 CPU, 8GB Memory\")"
}

variable "plan_provision_type" {
  type        = string
  description = "Provision type CODE the plan is looked up under (the hpe_morpheus_service_plan data source filters by provision_type_code; \"kvm\" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME \"KVM\"). Empty = match the plan by name alone."
  default     = "kvm"
}

variable "resource_pool_name" {
  type        = string
  description = "Name of the resource pool (the MVM/HVM cluster) to provision the instance to"
}

variable "network" {
  type        = string
  description = "Name of the Morpheus network the instance NIC joins (DHCP is assumed). Empty = the layout's default network selection; set it (plus network_interface_type_id) when the layout doesn't default one."
  default     = ""
}

variable "network_interface_type_id" {
  type        = number
  description = "Morpheus network interface TYPE ID for the NIC (required when network is set; the KVM virtio type on MVM clouds — look it up in the appliance)"
  default     = null
}

variable "root_volume" {
  type = object({
    size         = number
    datastore_id = number
    storage_type = optional(number, 1)
    name         = optional(string, "root")
  })
  description = "Optional explicit root volume {size (GB), datastore_id, storage_type, name}. null = the layout/plan defaults."
  default     = null
}

# tflint-ignore: terraform_unused_declarations # deliberate compat shim: validated-empty (HPE/hpe has no labels attribute)
variable "morpheus_labels" {
  type        = list(string)
  description = "MUST STAY EMPTY: the HPE/hpe provider's hpe_morpheus_instance exposes NO labels attribute (checked at v1.5.0; gomorpheus's morpheus_mvm_instance did), so Morpheus labels can't be applied from terraform anymore. The variable is kept (and validated empty) so existing callers passing [] keep working; set labels in the appliance instead."
  default     = []

  validation {
    condition     = length(var.morpheus_labels) == 0
    error_message = "morpheus_labels cannot be applied: hpe_morpheus_instance (HPE/hpe v1.5.0) has no labels attribute — the gomorpheus labels feature has no HPE equivalent yet. Leave empty and set labels via the appliance."
  }
}

# --- Instance shape -----------------------------------------------------------
variable "vm_name" {
  type        = string
  description = "Name for the k3s instance (also its hostname, and the prefix of the bootstrap task/workflow names — unique per appliance)"
  default     = "k3s"
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
  description = "SSH user the kubeconfig fetch logs in as. The bootstrap creates it (and authorizes ssh_public_key) when the image doesn't ship it."
  default     = "ubuntu"
}

variable "ssh_private_key" {
  type        = string
  description = "PEM private key the kubeconfig fetch SSHes with. Its public half must be accepted by ssh_user — pass ssh_public_key (the bootstrap authorizes it) or bake it into the virtual image."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "Public key the bootstrap task authorizes for ssh_user. Empty = the image (or the Morpheus provisioning user's key pair) must already accept ssh_private_key."
  default     = ""
}

variable "kubeconfig_timeout" {
  type        = number
  description = "Seconds the kubeconfig fetch waits for provisioning + the k3s bootstrap to finish"
  default     = 600
}

variable "update_kubeconfig" {
  type        = bool
  default     = true
  description = "Merge this cluster into the ambient kubeconfig (~/.kube/config, context k3s-<vm_name>) after creation and switch the current context to it — the on-prem analogue of the cloud modules' `update_kubeconfig`."
}

variable "instance_type_id" {
  type        = number
  description = "Literal instance-type id, bypassing the name lookup. REQUIRED on HPE VM Essentials: the hpe_morpheus_instance_type data source calls /api/library/instance-types, which 403s (templates=false) at PLAN time. null = resolve by name (full Morpheus, where the Library is licensed)."
  default     = null
}

variable "instance_layout_id" {
  type        = number
  description = "Literal layout id, bypassing the name lookup. REQUIRED on HPE VM Essentials (see instance_type_id). Also disambiguates: \"Single KVM VM\" is NOT unique — Ubuntu carries several. null = resolve by name."
  default     = null
}

variable "resource_pool_id" {
  type        = string
  description = "Literal resource-pool id, bypassing the name lookup. REQUIRED on HPE VM Essentials: it has no ResourcePool records (/api/resource-pools -> total=0) — the HVM cluster is a synthetic \"pool-<clusterId>\" served only by the zonePools option source, so the data source fails at PLAN time with \"found 0 resourcePools\". null = resolve by name (full Morpheus)."
  default     = null
}

variable "enable_provisioning_workflow" {
  type        = bool
  description = "Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task_set_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 \"Feature Not Included for the Applied License\", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap_task_ids for exactly that."
  default     = true
}
