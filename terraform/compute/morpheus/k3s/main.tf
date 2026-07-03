# Single-node k3s server on an HPE Morpheus instance — the on-prem "managed k8s"
# stand-in, sibling of compute/vsphere/k3s and compute/proxmox/k3s. Provisions ONE
# morpheus_mvm_instance (MVM — the KVM compute type of HPE VM Essentials / HVM and
# full Morpheus) from an EXISTING cloud/group/instance-type/layout/plan (Morpheus
# owns those concepts; this module looks them up by name) and installs k3s right
# after provisioning (bundled Traefik disabled — the traefik/k8s module deploys Hub;
# k3s's servicelb/klipper stays ON, so LoadBalancer Services get the node IP).
#
# BOOTSTRAP, the honest part: the gomorpheus terraform provider exposes NO
# user-data / cloud-config passthrough on its instance resources (verified against
# the provider schema — no such attribute exists on morpheus_mvm_instance), so the
# vSphere guestinfo / Proxmox snippet cloud-init delivery is off the table. Instead
# the module rides Morpheus's OWN provisioning pipeline: a shell-script TASK
# (morpheus_shell_script_task, execute_target=resource) wrapped in a provisioning
# WORKFLOW (postProvision phase) attached to the instance — the Morpheus agent runs
# it on the instance as provisioning completes. The same script authorizes the SSH
# public key, because the kubeconfig still has to be SSH-fetched (k3s mints client
# certs on the node; there is no API for them — see kubeconfig.tf) and the mvm
# instance resource has no key-pair attribute either.

data "morpheus_cloud" "this" {
  name = var.cloud
}

data "morpheus_group" "this" {
  name = var.group
}

data "morpheus_instance_type" "this" {
  name = var.instance_type
}

data "morpheus_instance_layout" "this" {
  name    = var.instance_layout
  version = var.instance_layout_version != "" ? var.instance_layout_version : null
}

data "morpheus_plan" "this" {
  name           = var.plan
  provision_type = var.plan_provision_type
}

data "morpheus_network" "this" {
  count = var.network != "" ? 1 : 0
  name  = var.network
}

locals {
  k3s_exec = join(" ", concat(
    ["server", "--disable", "traefik", "--write-kubeconfig-mode", "644"],
    var.tls_san != "" ? ["--tls-san", var.tls_san] : [],
    var.k3s_extra_args,
  ))

  # The kubeconfig fetch SSHes in as var.ssh_user; Morpheus offers no
  # terraform-side key injection on mvm instances, so the bootstrap authorizes
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
resource "morpheus_shell_script_task" "bootstrap" {
  name           = "${var.vm_name}-k3s-bootstrap"
  source_type    = "local"
  script_content = local.bootstrap
  execute_target = "resource"
  sudo           = true

  retryable           = true
  retry_count         = 3
  retry_delay_seconds = 15
}

resource "morpheus_provisioning_workflow" "bootstrap" {
  name     = "${var.vm_name}-k3s-bootstrap"
  platform = "linux"

  task {
    task_id    = morpheus_shell_script_task.bootstrap.id
    task_phase = "postProvision"
  }
}

resource "morpheus_mvm_instance" "k3s" {
  name               = var.vm_name
  cloud_id           = data.morpheus_cloud.this.id
  group_id           = data.morpheus_group.this.id
  instance_type_id   = data.morpheus_instance_type.this.id
  instance_layout_id = data.morpheus_instance_layout.this.id
  plan_id            = data.morpheus_plan.this.id
  resource_pool_name = var.resource_pool_name
  labels             = var.morpheus_labels

  # The agent is what executes the postProvision bootstrap — never skip it.
  skip_agent_install = false

  workflow_id = morpheus_provisioning_workflow.bootstrap.id

  dynamic "network_interface" {
    for_each = var.network != "" ? [1] : []
    content {
      network_id                = data.morpheus_network.this[0].id
      network_interface_type_id = var.network_interface_type_id
    }
  }

  dynamic "storage_volume" {
    for_each = var.root_volume != null ? [var.root_volume] : []
    content {
      root         = true
      name         = storage_volume.value.name
      size         = storage_volume.value.size
      datastore_id = storage_volume.value.datastore_id
      storage_type = storage_volume.value.storage_type
    }
  }

  lifecycle {
    # The workflow only runs at provision time — a bootstrap change must
    # recreate the instance (the same first-boot-only story as cloud-init).
    replace_triggered_by = [morpheus_shell_script_task.bootstrap]

    precondition {
      condition     = var.network == "" || var.network_interface_type_id != null
      error_message = "network_interface_type_id is required when network is set (the Morpheus API needs the interface type ID, e.g. the KVM virtio type)."
    }
  }
}
