# whoami on HPE Morpheus instances — the on-prem sibling of apps/whoami/ec2 /
# apps/whoami/azure-vm / apps/whoami/vsphere. Provisions N hpe_morpheus_instance
# on an MVM cloud (MVM — the KVM compute type of HPE VM Essentials / HVM;
# config_hvm is the KVM placement) per app and reuses the whoami/cloud-init
# template (docker-run systemd unit).
#
# LIKE EC2/Azure/OCI (and unlike vSphere's guestinfo JSON or Proxmox's Notes
# lines), the workload config IS dotted tags: Morpheus instance Tags are
# free-form name/value pairs, so each app's `traefik_labels` map lands 1:1 as
# instance tags and the Traefik Hub morpheus provider reads every `traefik.*`
# tag as a label — full label maps, the cloud-style story on-prem. Morpheus
# LABELS (plain strings) are a separate system the provider's `constraints`
# match — but the HPE/hpe provider can't SET them (hpe_morpheus_instance has no
# labels attribute as of v1.5.0, unlike gomorpheus's mvm_instance), so labels
# now have to be applied in the appliance, not from terraform.
#
# BOOTSTRAP, the honest part: the HPE/hpe terraform provider has NO
# user-data / cloud-config passthrough on its instance resource (verified
# against the v1.5.0 schema; neither did gomorpheus), so the composed
# whoami/cloud-init payload can't ride cloud-init here. Instead each
# app's rendered #cloud-config is CONVERTED (yamldecode, below) into a shell
# script — write_files become heredocs, runcmd entries run in order, each
# tolerated like cloud-init tolerates them — and delivered as a Morpheus
# shell-script TASK in a postProvision provisioning WORKFLOW, executed on the
# instance by the Morpheus agent. The template's users/chpasswd/ssh_pwauth
# convenience entries are NOT applied (Morpheus's own provisioning covers
# instance access); everything the workload needs is write_files + runcmd.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-vm).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

locals {
  # Replicate the ec2/azure-vm/vsphere siblings' instance-key scheme: "<app>-<replica>".
  instances = flatten([
    for app_name, app_config in var.apps : [
      for replica_idx in range(app_config.replicas) : {
        key            = "${app_name}-${replica_idx + 1}"
        app_name       = app_name
        traefik_labels = try(app_config.traefik_labels, {})
        labels         = try(app_config.labels, [])
      }
    ]
  ])

  instances_map = { for inst in local.instances : inst.key => inst }

  # The cloud-config -> shell adapter. Both shared cloud-init templates are
  # write_files + runcmd (plus access conveniences, skipped — see header), so
  # the conversion is mechanical and stays composed with whoami/cloud-init
  # rather than forking it.
  app_cloud_config = { for app, m in module.cloud_init : app => yamldecode(m.rendered) }

  app_bootstrap = { for app, cc in local.app_cloud_config : app => join("\n", concat(
    [
      "#!/usr/bin/env bash",
      "# Generated from apps/whoami/cloud-init's #cloud-config (see main.tf).",
      "set -u",
      "",
    ],
    flatten([for i, f in try(cc.write_files, []) : [
      "mkdir -p \"$(dirname '${f.path}')\"",
      "cat > '${f.path}' <<'TF_EOF_${i}'",
      trimsuffix(f.content, "\n"),
      "TF_EOF_${i}",
      "chown ${try(f.owner, "root:root")} '${f.path}'",
      "chmod ${try(f.permissions, "0644")} '${f.path}'",
      "",
    ]]),
    # Each runcmd entry runs in a subshell and a failure is logged, not fatal —
    # matching cloud-init's runcmd semantics (no -e across entries).
    flatten([for i, c in try(cc.runcmd, []) : [
      "(",
      trimsuffix(c, "\n"),
      ") || echo \"WARN: runcmd entry ${i} exited non-zero\"",
      "",
    ]]),
    ["exit 0"],
  )) }
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

data "hpe_morpheus_resource_pool" "this" {
  cloud_id = data.hpe_morpheus_cloud.this.id
  name     = var.resource_pool_name
}

# One task + workflow per APP (replicas share it) — appliance-level library
# items, so names derive from name_prefix + app (unique per appliance).
resource "hpe_morpheus_task_shell_script" "bootstrap" {
  for_each = var.apps

  name           = "${var.name_prefix}-${each.key}-bootstrap"
  source_type    = "local"
  script_content = local.app_bootstrap[each.key]
  execute_target = "resource"
  sudo           = true

  retryable           = true
  retry_count         = 3
  retry_delay_seconds = 15
}

resource "hpe_morpheus_workflow_provisioning" "bootstrap" {
  for_each = var.apps

  name     = "${var.name_prefix}-${each.key}-bootstrap"
  platform = "linux"

  task {
    # The HPE provider exposes task/workflow ids as strings but takes them as
    # numbers here (and on task_set_id below) — hence the tonumber()s.
    task_id    = tonumber(hpe_morpheus_task_shell_script.bootstrap[each.key].id)
    task_phase = "postProvision"
  }
}

resource "hpe_morpheus_instance" "whoami" {
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
    resource_pool_id = tostring(data.hpe_morpheus_resource_pool.this.id)
    no_agent         = false
  }

  # The morpheus provider's workload config: dotted Traefik labels as
  # name/value instance tags — the EC2/Azure-style tag model, on-prem.
  tags = length(each.value.traefik_labels) > 0 ? [
    for k, v in each.value.traefik_labels : { name = k, value = v }
  ] : null

  task_set_id = tonumber(hpe_morpheus_workflow_provisioning.bootstrap[each.value.app_name].id)

  # network_interfaces is REQUIRED by the provider schema; [] leans on the
  # layout's default network selection (gomorpheus's optional-NIC behavior).
  network_interfaces = var.network != "" ? [
    {
      network_id      = data.hpe_morpheus_network.this[0].id
      network_type_id = var.network_interface_type_id
    }
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
      condition     = var.network == "" || var.network_interface_type_id != null
      error_message = "network_interface_type_id is required when network is set (the Morpheus API needs the interface type ID, e.g. the KVM virtio type)."
    }

    precondition {
      # Morpheus labels can't be applied: hpe_morpheus_instance (HPE/hpe
      # v1.5.0) has no labels attribute — fail loudly instead of dropping them.
      condition     = length(each.value.labels) == 0
      error_message = "apps.${each.value.app_name}.labels cannot be applied: hpe_morpheus_instance (HPE/hpe v1.5.0) has no labels attribute — the gomorpheus labels feature has no HPE equivalent yet. Remove the labels entry and set labels via the appliance."
    }
  }
}
