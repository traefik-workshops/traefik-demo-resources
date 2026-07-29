# compute/gcp/vm

The shared Google Compute Engine VM primitive. Owns the `google_compute_instance`
(one per `instances` map entry) and an optional `google_compute_firewall`, and
nothing role-specific: the caller renders its own cloud-init, assembles the GCE
`metadata` map (including the `user-data` item and the single dotted-label
`traefik` JSON workload item) and the dotless `labels`, then hands them in per
instance. Both `traefik/gce` (the multicluster gateway, one VM) and
`apps/whoami/gce` (the echo backends, N VMs) compose this module.

The `network_ip` static pin lives here (per instance) so a hub dialing a child's
private IP is plan-known and stable across VM recreation. An attached service
account (the `gce` provider's ADC identity) is passed via `service_account`;
leave it `null` for backends that need no identity.

## Example usage

```hcl
module "compute" {
  source = "../../compute/gcp/vm"

  instances = {
    "whoami-1" = {
      metadata = { user-data = module.cloud_init["whoami"].rendered }
      labels   = { app = "whoami" }
    }
  }

  machine_type     = "e2-micro"
  zone             = "us-central1-a"
  network          = "default"
  enable_public_ip = false

  enable_firewall        = true
  tags                   = ["whoami"]
  firewall_ports         = ["80"]
  firewall_source_ranges = ["10.0.0.0/8"]
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
