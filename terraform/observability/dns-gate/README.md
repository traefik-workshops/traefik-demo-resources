# observability/dns-gate

A `null_resource` whose `local-exec` blocks until a hostname resolves in public
DNS, so that dependents are not created before it does. It owns nothing and
returns nothing but an `id` to hang a `depends_on` from.

It exists because of a specific, expensive failure. Every spoke in these demos
ships OTLP to `collector.<domain>`, a name the in-cluster `dns-traefiker`
publishes only after the hub's Traefik LoadBalancer Service gets an address.
Nothing ordered the spokes behind that, so they routinely booted first, and
their very first lookup returned NXDOMAIN — which resolvers **cache**, for the
zone's SOA MINIMUM (1800s on `traefik.ai`). Measured live on
`aws-unified-ingress`, 2026-08-11:

```
11:16:48  ECS tasks start, first OTLP export -> "no such host"
11:26:04  hub LoadBalancer Service created  (the name could not have existed before this)
11:28:36  dns-traefiker publishes the record
11:52:26  traefik-vm's first metrics land        <- ~30 min after the NXDOMAIN,
11:57:26  traefik-container's first metrics         not after the record appeared
```

Half an hour of serving every request correctly while reporting nothing. Routing
assertions pass, the service map comes back partial, and it reads as a broken
exporter. Resolution is checked from the operator's machine against a public
resolver, which is the right question to ask: the failure is caused by a lookup
happening too *early*, so what has to be established is that the name is
publicly resolvable before any spoke exists. A spoke created after that cannot
poison its own resolver.

## Read this before adding it to a demo

**This gate is necessary but not sufficient, and in two shapes it is actively
wrong.** Both were found live and both are documented at their sites.

**It cannot tell a live record from a dead one.** `dns-traefiker`'s wildcard for
a demo zone survives teardown. Measured 2026-08-11 with every cloud demo
destroyed, `collector.aws.demo.traefik.ai` *and* a random name under the same
zone still resolved — to the previous run's load balancer. On
`azure-unified-ingress` the gate returned `resolves -- spokes may boot` in one
second against an IP whose resource group had already been destroyed, and the
ACI leg's first export then failed with a **TCP timeout**, not NXDOMAIN. So on
any rebuild this gate is close to a no-op. Only the workload can settle the
question, from inside its own network: see `compute/azure/aci`'s
`otlp_gate_address` and `cloud-init-snippets/otlp-collector-gate.sh.tpl`, which
block until the endpoint *accepts* an OTLP write.

**Never gate a child whose address the hub consumes.** Where the hub's
multicluster children map dials a child gateway's *computed* address, gating that
child means the gate waits for a record whose publication it is itself blocking:
`gate -> child -> hub -> LoadBalancer -> dns-traefiker -> the record`. It is not
a cycle — the gate is anchored on the cluster — so `terraform validate` and
`terraform graph` both pass, and it only appears on a cold apply against a domain
that has never been built. `aws` and `azure` both shipped this and had to ungate
their container child; `oci` avoided it deliberately; `gcp` is immune only because
its uplink addresses are plan-known pinned locals.

**Demos whose guests never use a public resolver do not need it at all.** proxmox,
vsphere, morpheus and hyperv answer the demo domain from the lab router's dnsmasq
wildcard; suse's KubeVirt guests inherit their virt-launcher pod's `resolv.conf`
and dial the collector's in-cluster Service. None of them can produce the
NXDOMAIN this gate prevents, so adding it there is pure wait implying a
dependency that does not exist.

## Example usage

```hcl
module "otel_dns_gate" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/observability/dns-gate?ref=v6.6.0"

  hostname    = trimprefix(local.otel_collector_public, "https://")
  upstream_id = module.eks.cluster_endpoint
  # 1200s, not the 600s default: anchored on the cluster rather than the hub
  # Traefik (which cycles), the gate starts polling at cluster-ready and must
  # cover the Traefik install, LB provisioning, and dns-traefiker's publish.
  timeout_seconds = 1200
}

module "spoke_whoami" {
  source     = "...//terraform/apps/whoami/ec2?ref=v6.6.0"
  depends_on = [module.otel_dns_gate]
  # ...
}
```

Derive `hostname` from the same local the spokes are handed, rather than
rebuilding it from `var.domain`, so the gated name cannot drift from the
exported-to name.

## Prerequisites

- `dig` for the public-resolver query; without it the check falls back to the
  system resolver, which may hold its own negative-cache entry from an earlier
  run of the same demo.
- A `depends_on` from each dependent. An implicit reference is not enough — the
  dependent consumes no value from the gate, so terraform would otherwise be free
  to build them concurrently.

## Notes

- `upstream_id` is threaded into the triggers so a replaced publisher re-gates;
  anchor it on the cluster, never on the hub Traefik, which cycles through the
  observability module's scrape configs.
- The gate fails loudly rather than timing out silently, and its failure message
  names the two things actually worth checking: that `dns-traefiker` is running
  and that the hub's LoadBalancer Service got an address.
- Failing here is far cheaper than the blackout it prevents, which is why the
  default timeout is generous rather than tight.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.gate](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | The name that must resolve before dependents may be created — in these demos, the OTLP collector's public host (collector.<domain>). This is the name every spoke dials, so it is the one whose absence gets negatively cached. | `string` | n/a | yes |
| <a name="input_resolver"></a> [resolver](#input\_resolver) | Resolver the gate queries, as an address for `dig @<resolver>`. Default 1.1.1.1 (a PUBLIC resolver, so the operator's own negative cache cannot stall the gate). Set to "" to use the operator host's system resolver -- required on networks that block public DNS (the VCF lab console, 2026-08-22: port 53 to 1.1.1.1 times out), where the local resolver forwards public names and passes private answers. | `string` | `"1.1.1.1"` | no |
| <a name="input_timeout_seconds"></a> [timeout\_seconds](#input\_timeout\_seconds) | How long to wait for public resolution before failing. Default 600s: dns-traefiker publishes within ~2.5 minutes of the LoadBalancer getting an address, so this is generous without masking a genuinely broken DNS controller. Failing here is far cheaper than the 1800s telemetry blackout it prevents. | `number` | `600` | no |
| <a name="input_upstream_id"></a> [upstream\_id](#input\_upstream\_id) | An id from whatever publishes the record (the hub Traefik / observability module). Threading it through the triggers re-gates when that is replaced, so rebuilt infrastructure cannot let spokes race a freshly-published name. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Depend on this from every spoke that ships OTLP to the gated hostname. Use it in the spoke module's depends\_on — an implicit reference is not enough, because the spoke does not consume any value from the gate and terraform would otherwise be free to build them concurrently. |
<!-- END_TF_DOCS -->
