# traefik/

Traefik (the core demo subject for this repo) across every platform. Each platform module composes from `terraform/traefik/shared/`, which holds the configuration templating logic.

## Modules

| Path | Purpose |
|---|---|
| [`shared`](./shared) | **Heart of the section.** 42 variables, 40 outputs. Builds Traefik static config, CLI args, env vars, Helm values, etc. |
| [`cloud-init`](./cloud-init) | Cloud-init script that installs Traefik on a VM |
| [`aci`](./aci) | Traefik Hub as an ACI container group (`hub.providers.aci` + managed identity) |
| [`alibaba-eci`](./alibaba-eci) | Traefik Hub as an ECI container group (`hub.providers.alibabaECI` + instance RAM role) |
| [`alibaba-ecs`](./alibaba-ecs) | Traefik Hub on an Alibaba ECS instance (uses `cloud-init`; `hub.providers.alibabaECS` + instance RAM role) |
| [`azure-vm`](./azure-vm) | Traefik Hub on an Azure VM (uses `cloud-init`; `hub.providers.azureVM` + managed identity) |
| [`ec2`](./ec2) | Traefik on EC2 instances (uses `cloud-init`) |
| [`ecs`](./ecs) | Traefik on ECS Fargate |
| [`gce`](./gce) | Traefik Hub on a GCE VM (uses `cloud-init`; `hub.providers.gce` + attached service account) |
| [`k8s`](./k8s) | Traefik on Kubernetes via Helm (CRDs, IngressRoutes) |
| [`morpheus-vm`](./morpheus-vm) | Traefik Hub on an HPE Morpheus MVM instance (composes `cloud-init`, delivered as a Morpheus provisioning workflow; `hub.providers.morpheus` + explicit read-only credentials — API token XOR user/pass) |
| [`nutanix`](./nutanix) | Traefik on a Nutanix VM (uses `cloud-init`) |
| [`oci-ci`](./oci-ci) | Traefik Hub as an OCI Container Instance (`hub.providers.ociContainerInstances` + config-file auth) |
| [`oci-vm`](./oci-vm) | Traefik Hub on an OCI Compute VM (uses `cloud-init`; `hub.providers.oci` + instance principal) |
| [`proxmox-lxc`](./proxmox-lxc) | Traefik Hub in a Proxmox VE LXC container — the container half of the per-compute-type pair (no cloud-init: `pct exec` + the Hub binary crane-extracted from the image, run under systemd; same native `hub.providers.proxmox` discovery as `proxmox-vm`, scoped to LXC guests via `guest_types = ["lxc"]`; STATIC address — the hub must dial its uplink at a plan-time-known IP) |
| [`proxmox-vm`](./proxmox-vm) | Traefik Hub on a Proxmox VE VM (uses `cloud-init`; discovery via the native first-party `hub.providers.proxmox` provider — `--hub.providers.proxmox.*` flags, explicit read-only PVE API token) |
| [`vsphere-vm`](./vsphere-vm) | Traefik Hub on a vSphere VM (uses `cloud-init`; `hub.providers.vsphere` reading line-format `traefik.key=value` labels from the VM Notes + explicit read-only vCenter credentials — no ambient identity on-prem) |
| [`vmservice`](./vmservice) | The same child on a VM the vSphere Supervisor's VM Service provisions (`VirtualMachine` CRD in a vSphere Namespace; address known only after apply) |

## How `shared/` works

`terraform/traefik/shared/` is a **library module** — it has no resources. It accepts ~42 inputs describing the desired Traefik install (which gateways are enabled, what features, observability hooks, etc.) and emits ~40 outputs that downstream modules paste into their actual deployments.

Use it like this from a platform module:

```hcl
module "shared" {
  source = "../shared"

  # all the feature flags / config
  enable_api_gateway = var.enable_api_gateway
  enable_ai_gateway  = var.enable_ai_gateway
  # ...
}

resource "helm_release" "traefik" {
  values = [module.shared.helm_values_yaml]
}
```

If you're adding Traefik on a new platform, copy the closest existing platform module and re-use `shared/`.

## Feature flags

The most common knobs (set via `terraform/traefik/shared` or the platform module):

- `enable_api_gateway`
- `enable_ai_gateway`
- `enable_mcp_gateway`
- `enable_api_management`
- `enable_offline_mode`
- `enable_preview_mode`
- `enable_prometheus`
- `enable_otlp_metrics` / `_traces` / `_access_logs` / `_application_logs`
