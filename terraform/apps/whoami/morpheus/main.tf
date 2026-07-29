# whoami on HPE Morpheus instances — the on-prem sibling of apps/whoami/ec2 /
# apps/whoami/azure-vm / apps/whoami/vsphere. Provisions N hpe_morpheus_instance
# on an MVM cloud (MVM — the KVM compute type of HPE VM Essentials / HVM;
# config_hvm is the KVM placement) per app and reuses the whoami/cloud-init
# template (docker-run systemd unit). The instance + its Morpheus placement
# lookups + the bootstrap task/workflow DELIVERY infra live in the shared
# compute/morpheus/vm module — the same module traefik/morpheus-vm composes,
# exactly like whoami/ec2 + traefik/ec2 share compute/aws/ec2.
#
# LIKE EC2/Azure/OCI (and unlike vSphere's guestinfo JSON or Proxmox's Notes
# lines), the workload config IS dotted tags: Morpheus instance Tags are
# free-form name/value pairs, so each app's `traefik_labels` map lands 1:1 as
# instance tags (passed to the compute module as `tags`) and the Traefik Hub
# morpheus provider reads every `traefik.*` tag as a label — full label maps,
# the cloud-style story on-prem. Morpheus LABELS (plain strings) are a separate
# system the provider's `constraints` match — but the HPE/hpe provider can't SET
# them (hpe_morpheus_instance has no labels attribute as of v1.5.0, unlike
# gomorpheus's mvm_instance), so labels now have to be applied in the appliance,
# not from terraform (the `apps` variable validation rejects a non-empty labels
# entry).
#
# BOOTSTRAP, the honest part: the HPE/hpe terraform provider has NO
# user-data / cloud-config passthrough on its instance resource (verified
# against the v1.5.0 schema; neither did gomorpheus), so the composed
# whoami/cloud-init payload can't ride cloud-init here. Instead each
# app's rendered #cloud-config is CONVERTED (yamldecode, below) into a shell
# script HERE — write_files become heredocs, runcmd entries run in order, each
# tolerated like cloud-init tolerates them — and handed to the compute module as
# opaque user_data, which delivers it as a Morpheus shell-script TASK in a
# postProvision provisioning WORKFLOW, executed on the instance by the Morpheus
# agent. The template's users/chpasswd/ssh_pwauth convenience entries are NOT
# applied (Morpheus's own provisioning covers instance access); everything the
# workload needs is write_files + runcmd.

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

# =============================================================================
# Shared Compute Module — Morpheus VM
# =============================================================================
# One app per var.apps entry (replicas share the app's task/workflow); each
# app's rendered bootstrap SCRIPT (local.app_bootstrap[app]) is handed in as
# opaque user_data, and its traefik_labels ride `tags`. The bootstrap
# task/workflow are named "<name_prefix>-<app>-bootstrap" (unchanged). whoami
# pins no static IPs (private_ips = []), so NICs stay on DHCP / the layout pool.
# =============================================================================

module "compute" {
  source = "../../../compute/morpheus/vm"

  cloud                        = var.cloud
  group                        = var.group
  instance_type                = var.instance_type
  instance_layout              = var.instance_layout
  instance_layout_version      = var.instance_layout_version
  plan                         = var.plan
  plan_provision_type          = var.plan_provision_type
  resource_pool_name           = var.resource_pool_name
  network                      = var.network
  network_interface_type_id    = var.network_interface_type_id
  root_volume                  = var.root_volume
  instance_type_id             = var.instance_type_id
  instance_layout_id           = var.instance_layout_id
  resource_pool_id             = var.resource_pool_id
  computed_placement_ids       = var.computed_placement_ids
  enable_provisioning_workflow = var.enable_provisioning_workflow

  apps = {
    for app_name, app_config in var.apps : app_name => {
      replicas       = try(app_config.replicas, 1)
      user_data      = local.app_bootstrap[app_name]
      bootstrap_name = "${var.name_prefix}-${app_name}-bootstrap"
      tags           = try(app_config.traefik_labels, {})
      private_ips    = []
    }
  }
}
