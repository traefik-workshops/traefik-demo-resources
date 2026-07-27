# =============================================================================
# compute/morpheus/vm — inputs
# =============================================================================
# Everything here is INFRA (placement lookups + the instance shape). Nothing
# role-specific: the bootstrap SCRIPT arrives as an opaque per-app `user_data`,
# the workload labels as an opaque per-app `tags` map — the caller renders both.
# =============================================================================

variable "apps" {
  description = "Map of apps to provision as hpe_morpheus_instances. Key = the instance-name prefix, so each replica is \"<key>-<replica>\" (1-based), mirroring the ec2/azure-vm/vsphere sibling scheme. Per app: `replicas` (default 1); `user_data` — the ALREADY-RENDERED bootstrap shell script, delivered verbatim as the Morpheus task's script_content (OPAQUE to this module; the caller renders its own cloud-init and converts it to a shell script); `bootstrap_name` — the exact appliance-level library-item name for the task + provisioning workflow (unique per appliance); `tags` — dotted Traefik labels applied 1:1 as instance name/value tags (the Hub morpheus provider reads every traefik.* tag), {} => no tags (null); `private_ips` — fixed static IP per replica index (private_ips[replica] pins the NIC to ip_mode=static/ip_address; [] or a short list => DHCP / the layout's IP pool for the unpinned replicas)."
  type = map(object({
    replicas       = optional(number, 1)
    user_data      = string
    bootstrap_name = string
    tags           = optional(map(string), {})
    private_ips    = optional(list(string), [])
  }))
}

# --- Morpheus placement -------------------------------------------------------
variable "cloud" {
  description = "Name of the Morpheus cloud (e.g. the MVM/HVM cloud registered on the appliance) the instances are provisioned into"
  type        = string
}

variable "group" {
  description = "Name of the Morpheus group the instances belong to"
  type        = string
}

variable "instance_type" {
  description = "Name of the Morpheus instance type to provision from (e.g. \"Ubuntu\"). Must boot a cloud-init-enabled Linux image — the Morpheus agent (installed via cloud-init) runs the bootstrap."
  type        = string
  default     = "Ubuntu"
}

variable "instance_layout" {
  description = "Name of the instance layout under instance_type (e.g. \"Single KVM VM\")"
  type        = string
}

variable "instance_layout_version" {
  description = "Version of the instance layout (e.g. \"24.04\") — disambiguates layouts sharing a name. Empty = match by name alone."
  type        = string
  default     = ""
}

variable "plan" {
  description = "Name of the service plan — the plan IS the VM shape on Morpheus (no cpu/memory knobs here); pick one that fits the workload"
  type        = string
}

variable "plan_provision_type" {
  description = "Provision type CODE the plan is looked up under (the hpe_morpheus_service_plan data source filters by provision_type_code; \"kvm\" for MVM / HPE VM Essentials clouds — the gomorpheus-era value here was the NAME \"KVM\"). Empty = match the plan by name alone."
  type        = string
  default     = "kvm"
}

variable "resource_pool_name" {
  description = "Name of the resource pool (the MVM/HVM cluster) to provision the instances to"
  type        = string
}

variable "network" {
  description = "Name of the Morpheus network the instance NICs join (DHCP is assumed unless a per-app private_ips pin is set). Empty = the layout's default network selection."
  type        = string
  default     = ""
}

variable "network_interface_type_id" {
  description = "Morpheus network interface TYPE ID for the NICs (optional; VME does not require one)"
  type        = number
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

variable "computed_placement_ids" {
  type        = bool
  default     = false
  description = "Set true when instance_type_id / instance_layout_id / resource_pool_id are supplied from APPLY-TIME values (a data source or resource output, e.g. the demo's data.external.box_state). Those go unknown at destroy, and `count = var.<id> == null ? 1 : 0` then fails with \"Invalid count argument\". With this true the name-lookup count short-circuits to 0 on a known value (`true || unknown` = true in HCL), so destroy plans cleanly. Leave false when the ids are static literals or you resolve by name."
}

variable "enable_provisioning_workflow" {
  type        = bool
  description = "Wrap the bootstrap task in a Morpheus PROVISIONING WORKFLOW (a task-set) and attach it to each instance via task_set_id — the native path, which runs the bootstrap at postProvision. Requires features.workflows: HPE VM Essentials does NOT have it (POST /api/task-sets -> 403 \"Feature Not Included for the Applied License\", and the 403 fires before body validation). Set FALSE on VME and execute the task DIRECTLY instead — POST /api/tasks/{id}/execute is ungated (it answers 404 for a bogus id, not 403), and the task resource itself is fine (features.tasks=true). When false the CALLER owns triggering the bootstrap after provisioning; the module exposes bootstrap_task_ids for exactly that."
  default     = true
}
