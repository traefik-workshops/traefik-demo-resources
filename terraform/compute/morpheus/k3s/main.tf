# Single-node k3s server on an HPE Morpheus instance — the on-prem "managed k8s"
# stand-in, sibling of compute/vsphere/k3s and compute/proxmox/k3s. Provisions ONE
# hpe_morpheus_instance on an MVM cloud (MVM — the KVM compute type of HPE VM
# Essentials / HVM and full Morpheus; config_hvm below is the KVM placement) from
# an EXISTING cloud/group/instance-type/layout/plan (Morpheus owns those concepts;
# this module looks them up by name) and installs k3s right after provisioning
# (bundled Traefik disabled — the traefik/k8s module deploys Hub; k3s's
# servicelb/klipper stays ON, so LoadBalancer Services get the node IP).
#
# BOOTSTRAP, the honest part: the HPE/hpe terraform provider exposes NO
# user-data / cloud-config passthrough on its instance resource (verified against
# the v1.5.0 schema — no such attribute exists on hpe_morpheus_instance; neither
# did gomorpheus's morpheus_mvm_instance), so the vSphere guestinfo / Proxmox
# snippet cloud-init delivery is off the table. Instead the module rides
# Morpheus's OWN provisioning pipeline: a shell-script TASK
# (hpe_morpheus_task_shell_script, execute_target=resource) wrapped in a
# provisioning WORKFLOW (postProvision phase) attached to the instance via
# task_set_id — the Morpheus agent runs it on the instance as provisioning
# completes. The same script authorizes the SSH public key, because the
# kubeconfig still has to be SSH-fetched (k3s mints client certs on the node;
# there is no API for them — see kubeconfig.tf) and the instance resource has no
# key-pair attribute either.

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

locals {
  k3s_exec = join(" ", concat(
    ["server", "--disable", "traefik", "--write-kubeconfig-mode", "644"],
    var.tls_san != "" ? ["--tls-san", var.tls_san] : [],
    var.k3s_extra_args,
  ))

  # The kubeconfig fetch SSHes in as var.ssh_user; Morpheus offers no
  # terraform-side key injection on instances, so the bootstrap authorizes
  # the key itself (creating the user when the image doesn't ship it).
  authorize_key = var.ssh_public_key == "" ? "" : <<-EOT
    if ! id -u '${var.ssh_user}' >/dev/null 2>&1; then
      useradd -m -s /bin/bash '${var.ssh_user}'
    fi
    HOME_DIR="$(getent passwd '${var.ssh_user}' | cut -d: -f6)"
    install -d -m 0700 "$HOME_DIR/.ssh"
    grep -qF '${var.ssh_public_key}' "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null || printf '%s\n' '${var.ssh_public_key}' >> "$HOME_DIR/.ssh/authorized_keys"
    chmod 0600 "$HOME_DIR/.ssh/authorized_keys"
    chown -R '${var.ssh_user}:' "$HOME_DIR/.ssh"
  EOT

  bootstrap = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    ${local.authorize_key}
    curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL='${var.k3s_channel}' sh -s - ${local.k3s_exec}
  EOT
}

# The k3s install as a Morpheus library item. Task and workflow names must be
# unique per appliance, so they derive from vm_name — two stacks reusing the same
# vm_name on one appliance collide.
resource "hpe_morpheus_task_shell_script" "bootstrap" {
  name           = "${var.vm_name}-k3s-bootstrap"
  source_type    = "local"
  script_content = local.bootstrap
  execute_target = "resource"
  sudo           = true

  retryable           = true
  retry_count         = 3
  retry_delay_seconds = 15
}

resource "hpe_morpheus_workflow_provisioning" "bootstrap" {
  name     = "${var.vm_name}-k3s-bootstrap"
  platform = "linux"

  task {
    # The HPE provider exposes task/workflow ids as strings but takes them as
    # numbers here (and on task_set_id below) — hence the tonumber()s.
    task_id    = tonumber(hpe_morpheus_task_shell_script.bootstrap.id)
    task_phase = "postProvision"
  }
}

resource "hpe_morpheus_instance" "k3s" {
  name             = var.vm_name
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

  task_set_id = tonumber(hpe_morpheus_workflow_provisioning.bootstrap.id)

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
    # recreate the instance (the same first-boot-only story as cloud-init).
    replace_triggered_by = [hpe_morpheus_task_shell_script.bootstrap]

    precondition {
      condition     = var.network == "" || var.network_interface_type_id != null
      error_message = "network_interface_type_id is required when network is set (the Morpheus API needs the interface type ID, e.g. the KVM virtio type)."
    }
  }
}
