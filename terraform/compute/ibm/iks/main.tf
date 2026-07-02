# Managed IKS cluster on VPC gen2 — the IBM sibling of compute/alibaba/ack
# and compute/oracle/oke. Joins the provided subnets (e.g. compute/ibm/vpc's
# subnet_ids) instead of creating its own network; each subnet contributes a
# zone entry, and worker_count_per_zone workers land in every zone. IKS wants
# an explicit resource group ID — empty resolves to the account's default.

data "ibm_resource_group" "default" {
  count = var.resource_group_id == "" ? 1 : 0

  is_default = true
}

data "ibm_is_subnet" "selected" {
  for_each = toset(var.subnet_ids)

  identifier = each.value
}

locals {
  resource_group_id = var.resource_group_id != "" ? var.resource_group_id : data.ibm_resource_group.default[0].id

  # All subnets must live in one VPC — the cluster attaches to that VPC.
  vpc_id = data.ibm_is_subnet.selected[var.subnet_ids[0]].vpc
}

resource "ibm_container_vpc_cluster" "traefik_demo" {
  name              = var.cluster_name
  vpc_id            = local.vpc_id
  resource_group_id = local.resource_group_id

  kube_version = var.kube_version != "" ? var.kube_version : null

  flavor = var.cluster_node_type
  # IKS worker_count is PER ZONE: two subnets x the default 1 = 2 workers.
  worker_count = var.cluster_node_count_per_zone

  dynamic "zones" {
    for_each = data.ibm_is_subnet.selected

    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }

  # Don't block the apply on the ingress ALB (slowest readiness gate) — the
  # demos install Traefik themselves.
  wait_till = var.wait_till

  # The demo laptop and Terraform's kubernetes/helm providers dial the public
  # service endpoint directly.
  disable_public_service_endpoint = false

  # Demo-grade: let `terraform destroy` reclaim dynamically-provisioned
  # storage instead of orphaning it.
  force_delete_storage = true
}

# IKS kubeconfigs authenticate with an IAM OAuth token (no client certs), so
# the credential outputs mirror compute/oracle/oke: host + CA + token,
# straight off the cluster-config data source (the canonical IBM pattern for
# feeding the kubernetes/helm providers).
data "ibm_container_cluster_config" "traefik_demo" {
  cluster_name_id   = ibm_container_vpc_cluster.traefik_demo.id
  resource_group_id = local.resource_group_id
}
