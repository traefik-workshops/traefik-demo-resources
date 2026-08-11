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

  # Retried, and a failed LIST is never read as "already gone". These names are FIXED
  # (not per-run), so a survivor does not merely linger — it collides with the next run.
  # See the policy destroyer below for the full reasoning.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -eu
      REGION='${self.triggers.home_region}'
      TENANCY='${self.triggers.tenancy}'
      NAME='${self.triggers.name}'

      last=''
      i=1
      while [ $i -le 5 ]; do
        if ! listed=$(oci iam dynamic-group list --region "$REGION" --compartment-id "$TENANCY" --all --query "data[?name=='$NAME'].id | [0]" --raw-output 2>&1); then
          last="list failed: $listed"
        elif [ -z "$listed" ] || [ "$listed" = "null" ]; then
          exit 0
        elif deleted=$(oci iam dynamic-group delete --region "$REGION" --dynamic-group-id "$listed" --force 2>&1); then
          exit 0
        else
          last="delete failed: $deleted"
        fi
        echo "oci-instance-principal: dynamic group '$NAME' not gone yet (attempt $i/5): $last" >&2
        sleep $((i * 4))
        i=$((i + 1))
      done

      echo "oci-instance-principal: FAILED to delete tenancy dynamic group '$NAME' after 5 attempts." >&2
      echo "oci-instance-principal: last error: $last" >&2
      echo "oci-instance-principal: TENANCY-level IAM with a FIXED name — it survives the compartment" >&2
      echo "oci-instance-principal: teardown AND collides with the next run. Find it with:" >&2
      echo "oci-instance-principal:   oci iam dynamic-group list --region $REGION --compartment-id $TENANCY --all --query \"data[?name=='$NAME']\"" >&2
      exit 1
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
          --statements '["Allow dynamic-group ${local.dg_name} to read instance-family in compartment id ${var.compartment_id}", "Allow dynamic-group ${local.dg_name} to read virtual-network-family in compartment id ${var.compartment_id}"]' \
          --wait-for-state ACTIVE
      fi
    EOT
  }

  # Two failure modes, both ending the same way — a destroy that reports success while
  # tenancy IAM survives it. Identical to the pair fixed in traefik/oci-ci at v6.2.5;
  # this module was missed because the demo reaches tenancy IAM through TWO paths, and
  # only one of them was on the trail of the incident that prompted the fix.
  #
  # 1. The etag moves. This lives in the TENANCY ROOT, and identity-domain resources
  #    destroying alongside it write tenancy-scoped IAM too, so it can change between
  #    the list and the delete and OCI answers 412 NoEtagMatch. Re-listing each attempt
  #    is what makes the retry meaningful; a cached OCID would just 412 again.
  #
  # 2. A failed LIST was read as absence. `|| true` collapsed "the API would not answer"
  #    into "" and the `if [ -n "$id" ]` guard then skipped the delete and exited 0. One
  #    throttle was enough to leave tenancy IAM behind AND call the teardown clean.
  #
  # Worse here than in oci-ci: these names are FIXED (`instance-principals-traefik-demo`),
  # not per-run. A survivor is not a stale object nobody looks at — the next run's
  # idempotent create sees the name, skips creation, and silently inherits whatever
  # matching rule and policy statements the previous run left behind. verify-down-oci.sh
  # cannot see any of this; it sweeps the COMPARTMENT.
  #
  # Bounded at 5 attempts, 4s linear backoff, then it fails LOUDLY.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -eu
      REGION='${self.triggers.home_region}'
      TENANCY='${self.triggers.tenancy}'
      NAME='${self.triggers.name}'

      last=''
      i=1
      while [ $i -le 5 ]; do
        if ! listed=$(oci iam policy list --region "$REGION" --compartment-id "$TENANCY" --all --query "data[?name=='$NAME'].id | [0]" --raw-output 2>&1); then
          last="list failed: $listed"
        elif [ -z "$listed" ] || [ "$listed" = "null" ]; then
          exit 0
        elif deleted=$(oci iam policy delete --region "$REGION" --policy-id "$listed" --force 2>&1); then
          exit 0
        else
          last="delete failed: $deleted"
        fi
        echo "oci-instance-principal: policy '$NAME' not gone yet (attempt $i/5): $last" >&2
        sleep $((i * 4))
        i=$((i + 1))
      done

      echo "oci-instance-principal: FAILED to delete tenancy policy '$NAME' after 5 attempts." >&2
      echo "oci-instance-principal: last error: $last" >&2
      echo "oci-instance-principal: TENANCY-level IAM with a FIXED name — it survives the compartment" >&2
      echo "oci-instance-principal: teardown AND the next run will silently reuse it. Find it with:" >&2
      echo "oci-instance-principal:   oci iam policy list --region $REGION --compartment-id $TENANCY --all --query \"data[?name=='$NAME']\"" >&2
      exit 1
    EOT
  }
}
