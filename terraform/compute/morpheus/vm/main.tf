# =============================================================================
# compute/morpheus/vm — shared HPE Morpheus VM instances
# =============================================================================
# One hpe_morpheus_instance per app replica on an MVM cloud (MVM — the KVM
# compute type of HPE VM Essentials / HVM; config_hvm is the KVM placement),
# shared by traefik/morpheus-vm (the gateway, one instance) and
# apps/whoami/morpheus (N workloads) exactly like traefik/ec2 + whoami/ec2 share
# compute/aws/ec2. The module owns the infra — the instance, its Morpheus
# placement lookups, and the config-DELIVERY infra (the bootstrap shell-script
# task + provisioning workflow) — and takes the already-rendered bootstrap
# SCRIPT as an opaque per-app `user_data`. It owns NOTHING role-specific: the
# caller renders its own cloud-init, converts it to the shell script, and passes
# the result (plus the workload's `tags`) in.
#
# BOOTSTRAP: the HPE/hpe terraform provider has NO user-data / cloud-config
# passthrough on its instance resource (verified against the v1.5.0 schema;
# neither did gomorpheus), so the caller's rendered #cloud-config-as-shell-script
# is delivered as a Morpheus shell-script TASK in a postProvision provisioning
# WORKFLOW, executed on the instance by the Morpheus agent.
#
# hpe_morpheus_instance has NO labels attribute (checked at v1.5.0, unlike
# gomorpheus's mvm_instance), so Morpheus LABELS can't be set from terraform —
# the callers validate they stay empty; only the tag model is available here.
# =============================================================================

locals {
  # Flatten apps -> instances on the ec2/azure-vm/vsphere sibling key scheme:
  # "<app>-<replica>" (1-based). replica_index (0-based) indexes private_ips.
  instances = flatten([
    for app_name, app in var.apps : [
      for i in range(app.replicas) : {
        key           = "${app_name}-${i + 1}"
        app_name      = app_name
        replica_index = i
        tags          = app.tags
        private_ips   = app.private_ips
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }
}

data "hpe_morpheus_cloud" "this" {
  name = var.cloud
}

data "hpe_morpheus_group" "this" {
  name = var.group
}

# LIBRARY-GATED — both of these resolve by NAME through /api/library/*, which answers 403
# {"success":false,"msg":"Feature Not Included for the Applied License"} on an HPE VM Essentials
# licence (features.templates=false). That fails at PLAN time, before anything can run, and the
# by-id branch of these data sources is gated too (GetInstanceType -> /api/library/instance-types/{id},
# GetLayout -> /api/library/layouts/{id}) — so they cannot be re-parameterised, only bypassed.
# The escape: pass literal ids. hpe_morpheus_instance itself NEVER calls the Library API, so
# provisioning works fine with ids alone. Kept name-based by default for full Morpheus, where the
# Library IS licensed and names are friendlier than per-appliance ids.
data "hpe_morpheus_instance_type" "this" {
  count = var.instance_type_id == null ? 1 : 0
  name  = var.instance_type
}

data "hpe_morpheus_instance_type_layout" "this" {
  count   = var.instance_layout_id == null ? 1 : 0
  name    = var.instance_layout
  version = var.instance_layout_version != "" ? var.instance_layout_version : null
}

data "hpe_morpheus_service_plan" "this" {
  name                = var.plan
  provision_type_code = var.plan_provision_type != "" ? var.plan_provision_type : null
}

data "hpe_morpheus_network" "this" {
  count = var.network != "" ? 1 : 0
  name  = var.network
}

# On HPE VM Essentials there are NO ResourcePool records at all: /api/zones/{id}/resource-pools
# and /api/resource-pools both return total=0, and the cluster's own .resourcePool is null. VME
# exposes the HVM cluster as a SYNTHETIC pool ("pool-<clusterId>") through the zonePools option
# source only, so this data source can never find it ("found 0 resourcePools for <name>") — at
# PLAN time. Pass var.resource_pool_id to bypass it; config_hvm.resource_pool_id is a string
# anyway, which is exactly what "pool-1" is. Kept for full Morpheus, where real pools exist.
data "hpe_morpheus_resource_pool" "this" {
  count    = var.resource_pool_id == null ? 1 : 0
  cloud_id = data.hpe_morpheus_cloud.this.id
  name     = var.resource_pool_name
}

# One task + workflow per APP (replicas share it) — appliance-level library
# items; the caller supplies the exact library-item name (bootstrap_name) and
# the rendered bootstrap SCRIPT (user_data). NB the script carries whatever
# secrets the caller baked in (Hub token, provider credential) — demo-grade,
# appliance admins can read library tasks.
resource "hpe_morpheus_task_shell_script" "bootstrap" {
  for_each = var.apps

  name           = each.value.bootstrap_name
  source_type    = "local"
  script_content = each.value.user_data
  execute_target = "resource"
  sudo           = true

  retryable           = true
  retry_count         = 3
  retry_delay_seconds = 15
}

resource "hpe_morpheus_workflow_provisioning" "bootstrap" {
  for_each = var.enable_provisioning_workflow ? var.apps : {}

  name     = each.value.bootstrap_name
  platform = "linux"

  task {
    # The HPE provider exposes task/workflow ids as strings but takes them as
    # numbers here (and on task_set_id below) — hence the tonumber()s.
    task_id    = tonumber(hpe_morpheus_task_shell_script.bootstrap[each.key].id)
    task_phase = "postProvision"
  }
}

resource "hpe_morpheus_instance" "this" {
  for_each = local.instances_map

  name             = each.key
  cloud_id         = data.hpe_morpheus_cloud.this.id
  group_id         = data.hpe_morpheus_group.this.id
  instance_type_id = var.instance_type_id != null ? var.instance_type_id : one(data.hpe_morpheus_instance_type.this[*].id)
  layout_id        = var.instance_layout_id != null ? var.instance_layout_id : one(data.hpe_morpheus_instance_type_layout.this[*].id)
  plan_id          = data.hpe_morpheus_service_plan.this.id

  # KVM/MVM placement. no_agent defaults to TRUE on this provider (gomorpheus
  # installed the agent by default) and the agent is what executes the
  # postProvision bootstrap — never skip it.
  config_hvm = {
    resource_pool_id = var.resource_pool_id != null ? var.resource_pool_id : tostring(one(data.hpe_morpheus_resource_pool.this[*].id))
    no_agent         = false
  }

  # The morpheus provider's workload config: dotted Traefik labels as
  # name/value instance tags — the EC2/Azure-style tag model, on-prem.
  tags = length(each.value.tags) > 0 ? [
    for k, v in each.value.tags : { name = k, value = v }
  ] : null

  # null when the workflow is off (VME: /api/task-sets is 403). task_set_id is OPTIONAL in the
  # provider schema, so a null plans and applies clean — the instance simply provisions without a
  # postProvision hook, and the caller executes the task directly instead (see
  # bootstrap_task_ids). Do NOT "fix" this by making it required.
  task_set_id = var.enable_provisioning_workflow ? tonumber(hpe_morpheus_workflow_provisioning.bootstrap[each.value.app_name].id) : null

  # network_interfaces is REQUIRED by the provider schema; [] leans on the
  # layout's default network selection (gomorpheus's optional-NIC behavior).
  network_interfaces = var.network != "" ? [
    merge(
      {
        network_id      = data.hpe_morpheus_network.this[0].id
        network_type_id = var.network_interface_type_id
      },
      # Static assignment when pinned: the interface's ip_mode/ip_address (verified
      # present on hpe_morpheus_instance v1.5.0) give a plan-known, recreation-stable
      # address the parent can dial. Empty private_ips leaves both unset -> the
      # appliance's default (DHCP / IP pool), the prior behavior.
      try(each.value.private_ips[each.value.replica_index], "") != "" ? {
        ip_mode    = "static"
        ip_address = each.value.private_ips[each.value.replica_index]
      } : {}
    )
  ] : []

  volumes = var.root_volume != null ? [
    {
      root_volume     = true
      name            = var.root_volume.name
      size            = var.root_volume.size
      datastore_id    = var.root_volume.datastore_id
      storage_type_id = var.root_volume.storage_type
    }
  ] : null

  lifecycle {
    # The workflow only runs at provision time — a bootstrap change must
    # recreate the instances (the same first-boot-only story as cloud-init).
    # replace_triggered_by can't index by each.value, so ANY app's task change
    # re-provisions the whole fleet — fine for a demo-sized module.
    replace_triggered_by = [hpe_morpheus_task_shell_script.bootstrap]

    precondition {
      # network_interface_type_id is OPTIONAL, despite the gomorpheus-era assumption this used to
      # encode. VERIFIED on a live VME 9.0.0 appliance: POST /api/instances with
      # networkInterfaces:[{"network":{"id":1}}] and NO type at all provisions fine (instance
      # reached running). The NIC-type option sources are empty there anyway
      # (/api/options/networkInterfaceTypes -> []), so demanding one made the module unusable on
      # VME. Kept as a soft check only for the case where a caller sets the id to something
      # nonsensical; a null is legitimate.
      condition     = var.network == "" || var.network_interface_type_id == null || var.network_interface_type_id > 0
      error_message = "network_interface_type_id must be a positive Morpheus interface-type id when set (null is fine — VME does not require one)."
    }
  }
}
