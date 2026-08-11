# compute/azure/aci

Shared `azurerm_container_group` fleet composed by both `traefik/aci` (the Hub multicluster child) and `apps/whoami/aci` (the whoami backend), the ACI analogue of `compute/aws/ec2`.

Owns ONLY the container group resource. Everything role-specific is rendered by the caller and passed in as opaque inputs: the container `commands` (the Traefik child inlines its `--hub.token`; whoami passes `/whoami --verbose`), the discovery `tags`, the container `environment_variables`, the file-provider secret `volumes`, and whether a system-assigned `identity` is attached. One container group is created per entry in `container_groups` — the traefik caller passes a single entry, whoami one per app replica.

## Example usage

```hcl
module "compute" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/azure/aci?ref=v6.1.6"

  resource_group_name = azurerm_resource_group.demo.name
  location            = "eastus"
  subnet_id           = module.vnet.aci_subnet_id # delegated to Microsoft.ContainerInstance

  container_name   = "whoami"
  image            = "ghcr.io/traefik-workshops/whoami:latest"
  container_cpu    = "0.5"
  container_memory = "1.0"
  commands         = ["/whoami", "--verbose"]

  container_groups = {
    "whoami-1" = {
      ports                 = [80]
      environment_variables = { WHOAMI_NAME = "whoami-1" }
      tags                  = { "traefik.enable" = "true" }
    }
  }
}
```

## Prerequisites

- An existing resource group and a subnet delegated to `Microsoft.ContainerInstance` for `Private` groups (see `compute/azure/vnet`).

## The OTLP collector gate

Set `otlp_gate_address` whenever the workload exports telemetry:

```hcl
otlp_gate_address = "https://collector.example.com"
```

It adds an init container that blocks the workload from starting until that endpoint
**accepts an OTLP write** — bounded at 30 minutes, then starts anyway. It renders the same
`cloud-init-snippets/otlp-collector-gate.sh.tpl` that every VM leg in this library already
runs on first boot; containers just needed a different delivery, because the workload images
here are scratch and there is no cloud-init to hook.

Why it is not optional in practice: an exporter that makes its first export against an
endpoint that is not up yet stays dark, and the whoami fork's SDK has no recovery path at
all. That is a leg that serves every request perfectly and reports nothing — routing tests
pass over it, and it shows up only as a name missing from the service map.

**Do not gate a container the collector's own existence depends on.** In the unified-ingress
demos the hub consumes the ACI *gateway's* private IP as its uplink address, and the hub is
what brings the collector up — so gating that container makes it wait for an endpoint that
cannot exist until it starts. Bounded at 30 minutes instead of fatal, which reads as a slow
demo rather than a broken one and is harder to find. `traefik/aci` therefore leaves the gate
off and says so; `apps/whoami/aci` turns it on, because nothing is built on top of a backend.
Trace what consumes a container's outputs before gating it.

**Terraform-side ordering does not substitute for this.** `observability/dns-gate` waits for
the collector's DNS name to resolve, and a name resolves perfectly well while it still points
at the *previous* run's load balancer: on azure-unified-ingress (2026-08-11) that gate
returned `resolves -- spokes may boot` in one second, against an IP whose resource group had
already been destroyed. In these demos it is also upstream of the hub that publishes the
record, so on a genuinely cold domain it waits for something its own dependents must be
created before anything can publish. Only the workload can ask the question that settles it,
and only from inside its own network.

## Notes

- ACI vnet-injected groups get a DHCP address from the delegated subnet; there is no static `private_ip` argument to pin (unlike the VM/EC2 siblings).
- `enable_system_identity` applies to every group in the call; when set, `instances[<key>].principal_id` exposes the identity for a downstream role assignment.
- `otlp_gate_image` only needs a shell and curl; it defaults to `curlimages/curl:8.14.1`. Init containers run to completion in order before the main container, and the gate always exits 0 — a non-zero exit would leave the group restarting instead of degrading to "runs, reports late".
