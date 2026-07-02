# apps/

Sample workloads used to demonstrate infrastructure. These are deliberately trivial — they exist so an SA can point at *something* running after `terraform apply`.

If you're tempted to put real application logic here, stop. Real apps live in their own repos.

## Modules

| Path | Platform | Purpose |
|---|---|---|
| [`httpbin/k8s`](./httpbin/k8s) | k8s | httpbin in-cluster — useful for testing ingress, headers, redirects |
| [`whoami/aci`](./whoami/aci) | Azure | whoami as ACI container groups (private vnet-injected IPs) |
| [`whoami/azure-vm`](./whoami/azure-vm) | Azure | whoami on Azure Linux VMs (uses `whoami/cloud-init`) |
| [`whoami/cloud-init`](./whoami/cloud-init) | template | Cloud-init script that docker-runs the whoami image (default: OTel-instrumented `zalbiraw/whoami` fork) on a VM |
| [`whoami/cloudrun`](./whoami/cloudrun) | GCP | whoami as Cloud Run v2 services (traefik.* annotations; optional gen2 function) |
| [`whoami/ec2`](./whoami/ec2) | AWS | whoami on EC2 (uses `whoami/cloud-init`) |
| [`whoami/ecs`](./whoami/ecs) | AWS | whoami on ECS Fargate |
| [`whoami/gce`](./whoami/gce) | GCP | whoami on GCE VMs (traefik config via the `traefik` JSON metadata item; uses `whoami/cloud-init`) |
| [`whoami/k8s`](./whoami/k8s) | k8s | whoami in-cluster, with optional Traefik IngressRoute |
| [`whoami/nutanix`](./whoami/nutanix) | Nutanix | whoami on a Nutanix VM |
| [`whoami/nutanix/image_builder`](./whoami/nutanix/image_builder) | Nutanix | Builds a Nutanix image baked with whoami |
| [`whoami/oci-ci`](./whoami/oci-ci) | OCI | whoami as OCI Container Instances (private VNIC IPs; declared port via TCP health check) |
| [`whoami/oci-vm`](./whoami/oci-vm) | OCI | whoami on OCI Compute VMs (traefik config via dotted freeform tags; uses `whoami/cloud-init`) |

## When to add an app

Almost never. The bar is: "is there a *demo concept* that whoami and httpbin can't carry?" If yes, add it. If no, use what's here.

The most common request is "an app that does X behavior" (slow response, error injection, large payload). Prefer adding a flag to `whoami/k8s` if possible.
