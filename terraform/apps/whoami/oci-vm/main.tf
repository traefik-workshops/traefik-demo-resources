# whoami on OCI Compute VMs — the OCI sibling of apps/whoami/ec2 and
# apps/whoami/azure-vm. Reuses the whoami/cloud-init template (docker-run
# systemd unit); each app replica is one small VM whose FREEFORM TAGS (dotted
# keys, exactly like EC2/Azure tags) are the workload config a Traefik Hub
# oci provider (traefik/oci-vm) discovers.

module "cloud_init" {
  for_each = var.apps
  source   = "../cloud-init"

  whoami_image   = var.whoami_image
  whoami_version = var.whoami_version
  port           = try(each.value.port, 80)
  # WHOAMI_NAME on the container -> body shows `Name: <name>` (e.g. whoami-oci-vm).
  name = try(each.value.name, "")
  # Per-app env wins over module-level env on collision.
  environment = merge(var.environment, try(each.value.environment, {}))
}

# The VMs live in the shared compute module — one instance per app, expanded to
# <app>-<replica> keys inside the module (traefik/oci-vm composes the same one).
# The dotted-key traefik.* freeform tags (the oci provider's workload config,
# exactly like EC2 instance tags) and the rendered cloud-init are passed in.
module "compute" {
  for_each = var.apps
  source   = "../../../compute/oracle/vm"

  name           = each.key
  replicas       = each.value.replicas
  compartment_id = var.compartment_id

  availability_domain = var.availability_domain
  subnet_id           = var.subnet_id
  nsg_ids             = var.nsg_ids

  shape         = var.shape
  ocpus         = var.ocpus
  memory_in_gbs = var.memory_in_gbs
  vm_image_ocid = var.vm_image_ocid

  enable_public_ip = var.enable_public_ip

  user_data     = module.cloud_init[each.key].rendered
  freeform_tags = merge(var.common_tags, try(each.value.tags, {}))
}
