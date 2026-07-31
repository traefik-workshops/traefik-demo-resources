# compute/oracle/vm

Shared OCI Compute instance module. Provisions `replicas` `oci_core_instance`
VMs (keyed `<name>-<replica>`) from the latest Canonical Ubuntu 24.04 platform
image (or an explicit image OCID), with optional static private-IP pinning,
public IP, freeform tags, and opaque cloud-init user data. Both
`traefik/oci-vm` (the multicluster gateway, `replicas = 1`) and
`apps/whoami/oci-vm` (the echo backends, `replicas = N`) compose it.

Role-specific concerns stay in the callers: cloud-init rendering, the
instance-principal credential, dashboard self-registration tags, and NSG
creation. The module receives their results as opaque inputs.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/oracle/vm?ref=v5.2.1"

  name           = "traefik"
  replicas       = 1
  compartment_id = var.compartment_id
  subnet_id      = var.subnet_id
  user_data      = local.rendered_cloud_init
}
```

## Prerequisites

- A reachable OCI tenancy and a compartment the caller's credentials can create
  instances in.
- A subnet OCID the VNIC(s) join.
