# compute/oracle/vm — the shared OCI Compute instance both traefik/oci-vm (the
# multicluster gateway, replicas = 1) and apps/whoami/oci-vm (the echo backends,
# replicas = N) compose. Owns ONLY the instance + the AD/image lookups it needs
# to resolve placement and boot image; the callers keep every role-specific
# concern (cloud-init rendering, instance-principal auth, dashboard tags, NSG
# creation) and pass the results in as opaque inputs.

data "oci_identity_availability_domains" "this" {
  compartment_id = var.compartment_id
}

# Latest Canonical Ubuntu 24.04 platform image for the chosen shape — the same
# OS the azure-vm/gce siblings run (the cloud-init installs docker via apt).
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.this.availability_domains[0].name
  image_id            = var.vm_image_ocid != "" ? var.vm_image_ocid : data.oci_core_images.ubuntu.images[0].id

  # "<name>-<replica>" keys, mirroring compute/aws/ec2 (traefik-1, whoami-oci-vm-1, …).
  instances = { for idx in range(var.replicas) : "${var.name}-${idx + 1}" => idx }
}

resource "oci_core_instance" "vm" {
  for_each = local.instances

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_id
  display_name        = each.key
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = var.enable_public_ip
    private_ip       = try(var.private_ips[each.value], null)
    nsg_ids          = var.nsg_ids
  }

  source_details {
    source_type = "image"
    source_id   = local.image_id
  }

  metadata = {
    user_data = base64encode(var.user_data)
  }

  freeform_tags = var.freeform_tags
}
