# compute/oracle/ci

Provisions a fleet of OCI Container Instances from an `instances` map (one
`oci_container_instances_container_instance` per entry) and resolves each
instance's private VNIC IP. The per-instance container definition (image,
command, environment, health check, mounts) and CONFIGFILE volumes are passed in
as opaque structured payloads — this module owns only the infrastructure
resource, no role-specific (Traefik Hub / whoami) logic.

Shared by `traefik/oci-ci` (one instance — the multicluster child) and
`apps/whoami/oci-ci` (N instances — the discovered workloads).

## Example usage

```hcl
module "ci" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/oracle/ci?ref=v6.0.0"

  compartment_id = var.compartment_id
  subnet_id      = var.subnet_id

  instances = {
    "whoami-1" = {
      display_name = "whoami-1"
      containers = [{
        display_name = "whoami"
        image_url    = "ghcr.io/traefik-workshops/whoami:latest"
        environment_variables = {
          WHOAMI_NAME = "whoami-1"
        }
        health_checks = {
          health_check_type = "TCP"
          port              = 80
        }
      }]
    }
  }
}
```

## Prerequisites

- OCI credentials with Container Instances / networking permissions.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
