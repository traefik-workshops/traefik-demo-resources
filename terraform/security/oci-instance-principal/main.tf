locals {
  dg_name       = "instance-principals-traefik-demo"
  policy_name   = "instance-principals-traefik-demo"
  matching_rule = "ALL {instance.compartment.id = '${var.compartment_id}'}"
}

# OCI IAM (dynamic groups + policies) is tenancy-level and can only be WRITTEN
# against the tenancy home region. The demo's default OCI provider targets the
# workload region, so the terraform-native oci_identity_* resources fail with
# "must be in home region" and (for dynamic groups) "must be in the root
# compartment". Both are therefore created via the OCI CLI (local-exec) against
# var.home_region and the tenancy root compartment. Idempotent: create only when
# the named object is absent; destroy removes it by looked-up OCID.
resource "null_resource" "dynamic_group" {
  triggers = {
    name        = local.dg_name
    home_region = var.home_region
    tenancy     = var.tenancy_id
    rule        = local.matching_rule
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      existing=$(oci iam dynamic-group list --region ${var.home_region} --compartment-id ${var.tenancy_id} --all --query "data[?name=='${local.dg_name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -z "$existing" ] || [ "$existing" = "null" ]; then
        oci iam dynamic-group create --region ${var.home_region} --compartment-id ${var.tenancy_id} \
          --name '${local.dg_name}' --description 'Instance principals for the Traefik OCI demo' \
          --matching-rule "${local.matching_rule}" --wait-for-state ACTIVE
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -eu
      id=$(oci iam dynamic-group list --region ${self.triggers.home_region} --compartment-id ${self.triggers.tenancy} --all --query "data[?name=='${self.triggers.name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        oci iam dynamic-group delete --region ${self.triggers.home_region} --dynamic-group-id "$id" --force
      fi
    EOT
  }
}

resource "null_resource" "policy" {
  depends_on = [null_resource.dynamic_group]

  triggers = {
    name        = local.policy_name
    home_region = var.home_region
    tenancy     = var.tenancy_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      existing=$(oci iam policy list --region ${var.home_region} --compartment-id ${var.tenancy_id} --all --query "data[?name=='${local.policy_name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -z "$existing" ] || [ "$existing" = "null" ]; then
        oci iam policy create --region ${var.home_region} --compartment-id ${var.tenancy_id} \
          --name '${local.policy_name}' --description 'Instance principals policy for the Traefik OCI demo' \
          --statements '["Allow dynamic-group ${local.dg_name} to manage all-resources in tenancy"]' \
          --wait-for-state ACTIVE
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -eu
      id=$(oci iam policy list --region ${self.triggers.home_region} --compartment-id ${self.triggers.tenancy} --all --query "data[?name=='${self.triggers.name}'].id | [0]" --raw-output 2>/dev/null || true)
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        oci iam policy delete --region ${self.triggers.home_region} --policy-id "$id" --force
      fi
    EOT
  }
}
