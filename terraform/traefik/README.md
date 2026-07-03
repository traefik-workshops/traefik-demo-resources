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
| [`ibm-vpc`](./ibm-vpc) | Traefik Hub on an IBM VPC instance (uses `cloud-init`; `hub.providers.ibmVPC` + IAM API key — base-config-file discovery, no dotted tags) |
| [`k8s`](./k8s) | Traefik on Kubernetes via Helm (CRDs, IngressRoutes) |
| [`nutanix`](./nutanix) | Traefik on a Nutanix VM (uses `cloud-init`) |
| [`oci-ci`](./oci-ci) | Traefik Hub as an OCI Container Instance (`hub.providers.ociContainerInstances` + config-file auth) |
| [`oci-vm`](./oci-vm) | Traefik Hub on an OCI Compute VM (uses `cloud-init`; `hub.providers.oci` + instance principal) |
| [`vsphere-vm`](./vsphere-vm) | Traefik Hub on a vSphere VM (uses `cloud-init`; `hub.providers.vsphere` + explicit read-only vCenter credentials — no ambient identity on-prem) |

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
