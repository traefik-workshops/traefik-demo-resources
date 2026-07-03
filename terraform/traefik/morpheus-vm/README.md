# traefik/morpheus-vm

Traefik Hub on an **HPE Morpheus instance** (MVM — the KVM compute type of **VM Essentials / HVM** and full Morpheus) — the on-prem sibling of `traefik/ec2` / `traefik/azure-vm` / `traefik/vsphere-vm`. Provisions one `hpe_morpheus_instance` (on an MVM cloud; `config_hvm` carries the KVM placement) from an existing instance type/layout/plan, extracts its Traefik configuration from `traefik/shared` (via Helm template) and boots it with the shared `traefik/cloud-init` template — as a systemd binary, or as a docker container when `enable_preview_mode = true` (required while the `morpheus` provider isn't in a tagged Hub release).

## The morpheus provider

`var.morpheus_provider` renders `--hub.providers.morpheus.*` CLI flags. The gateway discovers workload instances by their **`traefik.*` instance tags** — dotted name/value pairs, the cloud-style label model (see `apps/whoami/morpheus`); `constraints` match Morpheus **labels** (as `label=true` pairs) plus a synthesized `name` pseudo-label — but the `HPE/hpe` terraform provider can't SET labels (`hpe_morpheus_instance` has no labels attribute as of v1.5.0), so apply them in the appliance. When no `server.port` label is set, the provider falls back to the **lowest port declared in the instance's connection info** (layout-declared) — set the label explicitly. `ipMode` `private` and `public` both resolve to an instance's primary connection address on-prem; `ipv6` picks the first IPv6 one; per-instance override via the `traefik.morpheus.ipmode` tag.

**Credentials are explicit** — the gateway's Init enforces **exactly one** auth method: `var.morpheus_access_token` (sensitive, **preferred** — mint it for a read-only user) OR `morpheus_provider.username` + `var.morpheus_password`. `endpoint` must be the **full appliance URL including the scheme** (Init rejects a bare host). The credential lands in the instance's bootstrap task and unit file — demo-grade; don't hand it an admin.

Routerless discovery (`default_rule = "{{/*routerless*/}}"`) works exactly like the EC2/Azure/vSphere siblings: instances land as services only, and routers come from file-provider rules.

## Bootstrap is a Morpheus provisioning workflow (read this)

The `HPE/hpe` terraform provider has **no user-data / cloud-config passthrough** on its instance resource (verified against the v1.5.0 schema; neither did gomorpheus), so the composed `traefik/cloud-init` payload is **converted in terraform** (`yamldecode`: `write_files` → heredocs, `runcmd` → tolerated sequential entries — cloud-init's own semantics) into a shell script delivered as an `hpe_morpheus_task_shell_script` in a `postProvision` `hpe_morpheus_workflow_provisioning`, executed by the **Morpheus agent**. Consequences: `config_hvm.no_agent` stays false (the provider default is agentless) and the layout must boot a **cloud-init-enabled Linux image**; config changes recreate the instance (`replace_triggered_by`); the template's `users`/`chpasswd` access conveniences are not applied; the task/workflow are appliance-level library items named `<vm_name>-traefik-bootstrap`.

## Example usage

```hcl
module "traefik_morpheus" {
  source = "git::https://github.com/traefik/traefik-demo.git//terraform/traefik/morpheus-vm?ref=v4.3.0"

  cloud              = "hvm-cloud"
  group              = "demo"
  instance_type      = "Ubuntu"
  instance_layout    = "Single KVM VM"
  plan               = "2 CPU, 4GB Memory"
  resource_pool_name = "hvm-cluster-01"

  traefik_hub_token   = var.traefik_hub_token
  enable_api_gateway  = true
  enable_offline_mode = true

  morpheus_provider = {
    endpoint = "https://morpheus.lab.example.com"
  }
  morpheus_access_token = var.morpheus_access_token # or username in the object + morpheus_password

  # Join a Hub mesh: uplink entrypoint on :9443, parent dials this instance's primary IP.
  multicluster_provider = { enabled = true }
  custom_ports = {
    vmuplink = {
      port   = 9443
      uplink = true
      expose = { default = true }
      http   = { tls = { enabled = true } }
    }
  }
}
```

## Prerequisites

- A Morpheus appliance (**VM Essentials / HVM** or full Morpheus) with an MVM cloud/group/instance type/layout/plan; terraform provider credentials allowed to create library tasks/workflows and provision instances — the gateway's read-only discovery credential can (and should) differ.
- A cloud-init-enabled Linux layout (agent-installable); DHCP on the network; `helm` on the machine running terraform (config extraction via `helm template`).

## Notes

- `enable_dashboard_discovery` (default on) self-registers the instance's dashboard through its own `traefik.*` tags (`dashboard@morpheus`); disable it when a file-rule uplink advertises the dashboard instead.
- Outputs mirror the VM siblings (`instances` / `private_ips` / `public_ips`) so demo code reads identically — on Morpheus both IP maps carry the same primary address.
- MIGRATED from the community-deprecated `gomorpheus/morpheus` provider (EOL Aug 2026) to the official `HPE/hpe` provider (`~> 1.5`). One functional loss: `hpe_morpheus_instance` has **no `labels` attribute** (v1.5.0), so `morpheus_labels` must stay empty (validated) — set Morpheus labels in the appliance instead. `plan_provision_type` is now the provision type **code** (`"kvm"`), not the name (`"KVM"`). State from gomorpheus deployments does not migrate — plan on recreating.
