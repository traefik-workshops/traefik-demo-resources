# compute/aws/ecs

Provisions one or more ECS clusters and the underlying task definitions/services from a nested `clusters` map.

## Example usage

```hcl
module "ecs" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/aws/ecs?ref=v6.2.8"

  name = "demo"
  clusters = {
    "demo" = {
      apps = {
        "whoami" = { docker_image = "traefik/whoami:latest", port = 80 }
      }
    }
  }
}
```

## Prerequisites

- AWS credentials with ECS/VPC permissions.

## The OTLP collector gate

`otlp_gate_address` adds an `otlp-collector-gate` sidecar that every task's main container
waits on (`dependsOn: SUCCESS`) until the collector accepts an OTLP write. It is the Fargate
form of `cloud-init-snippets/otlp-collector-gate.sh.tpl`, which every VM leg in this library
already runs at first boot; the container legs are scratch images with no cloud-init, so they
were the only ones that started exporting into the void. An exporter pointed at an endpoint
that is not up yet stays dark, and the whoami fork's SDK has no recovery path at all. That is
a leg that serves every request perfectly and reports nothing — routing tests pass over it,
and it shows up only as a name missing from the service map.

**It fails closed, and the budget is why that is safe.** `otlp_gate_rounds` (default 270 ×
10s = 45 min) has to outlast the 1800s SOA MINIMUM on `traefik.ai`, because that is how long a
resolver may keep serving the NXDOMAIN it cached before the collector's record was published.
The VM legs pass 180 rounds — exactly 1800s, no margin — and get away with it only because
they ignore the outcome and boot regardless. Here the gate exits non-zero on exhaustion and
`SUCCESS` turns that into a stopped task, so the budget has to be a real one.

Exhaustion is therefore a restart, not a release, and that is not a crash loop: every failure
path walks the whole budget before exiting, so one attempt costs 45 minutes, and ECS's own
throttle stretches the gap between launches up to a documented 27-minute maximum while
emitting `(service X) is unable to consistently start tasks successfully`. Retries continue
indefinitely, so the run self-heals the moment the collector answers. The alternative —
`COMPLETE` plus a gate that always exits 0 — releases the gateway on exhaustion, which is the
one failure the gate exists to prevent, arrived at silently. Note the restart is not what
re-resolves DNS: the gate re-resolves every 10 seconds anyway, and the negative cache lives in
the VPC resolver, which outlives the task. What the restart buys is a fresh budget and a
gateway that never starts exporting into a void.

**Do not gate a container the collector's own existence depends on.** Trace what consumes a
container's outputs before gating it. This warning used to name `traefik/ecs` as the container
that must stay ungated, because the hub consumes its NLB address as an uplink. That was wrong,
and `traefik/ecs` has gated since v6.2.6: the gate is a runtime sidecar rendered into the task
definition, it adds no terraform edge, and the NLB exists the moment terraform creates it
whether or not any container ever starts — so the hub still gets its address and still brings
the collector up. The rule that does bind is that `otlp_gate_address` must be **plan-known**
(built from the domain, never read off an attribute of the thing the gate waits for); a
computed address puts a real edge back into the graph and deadlocks the apply with no cycle
error, which neither `validate` nor `graph` catches.

**Terraform-side ordering does not substitute for this.** `observability/dns-gate` waits for
the collector's DNS name to resolve, and a name resolves perfectly well while it still points
at the *previous* run's load balancer: on aws-unified-ingress (2026-08-11) that gate returned
`resolves -- spokes may boot` in under a second — 19 seconds after the EKS cluster went
ACTIVE and minutes before this run's hub existed — against an ELB that had already been
destroyed. The tasks it released then logged `context deadline exceeded` for eleven minutes.
Worse, that gate sits upstream of the hub in those demos, so on a genuinely cold domain it
deadlocks the apply outright and fails it at the timeout.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb.nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.nlb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_clusters"></a> [clusters](#input\_clusters) | Map of ECS clusters with their applications | <pre>map(object({<br/>    apps = map(object({<br/>      replicas           = optional(number, 1)<br/>      subnet_ids         = optional(list(string), [])<br/>      port               = optional(number, 80)<br/>      docker_image       = optional(string, "traefik/whoami:latest")<br/>      docker_command     = optional(string, "")<br/>      labels             = optional(map(string), {})<br/>      environment        = optional(map(string), {})<br/>      security_group_ids = optional(list(string), [])<br/><br/>      # Fargate task needs egress to pull images; set true (the module places<br/>      # tasks in public subnets) unless a NAT-routed private subnet is supplied.<br/>      assign_public_ip = optional(bool, false)<br/><br/>      # If set, front the task with an NLB on this port (a stable address — the<br/>      # Fargate-equivalent of an EC2 Elastic IP). Targets the task's `port`.<br/>      nlb_port = optional(number, null)<br/><br/>      # Make that NLB internal (private IPs only) instead of internet-facing — for a<br/>      # parent that dials the spoke privately within a shared VPC. Needs private<br/>      # (NAT-routed) subnet_ids + assign_public_ip = false.<br/>      nlb_internal = optional(bool, false)<br/><br/>      # Ephemeral task volumes (names) + the main container's mounts, for delivering<br/>      # config files into a scratch image (e.g. a config-init sidecar writes them).<br/>      volumes      = optional(list(string), [])<br/>      mount_points = optional(list(object({ name = string, path = string })), [])<br/><br/>      # Container start ordering, e.g. wait for a config-init sidecar to COMPLETE.<br/>      depends_on = optional(list(object({<br/>        name      = string<br/>        condition = optional(string, "START") # START | COMPLETE | SUCCESS | HEALTHY<br/>      })), [])<br/><br/>      # ECS container health check, exec'd INSIDE the container. Required when the<br/>      # discovering Traefik runs with healthyTasksOnly=true: a task with no health<br/>      # check reports HealthStatus=UNKNOWN and is filtered out, emptying the service.<br/>      # Scratch images have no curl — the whoami fork ships a self-probe for this<br/>      # (command = ["CMD", "/whoami", "-health-check"]).<br/>      health_check = optional(object({<br/>        command      = list(string)<br/>        interval     = optional(number, 10) # seconds between probes<br/>        timeout      = optional(number, 5)<br/>        retries      = optional(number, 3)<br/>        start_period = optional(number, 15) # grace before failures count<br/>      }), null)<br/><br/>      # Extra containers in the same task (sidecars: config writers, co-located<br/>      # backends reachable on localhost, etc.).<br/>      sidecars = optional(list(object({<br/>        name         = string<br/>        image        = string<br/>        command      = optional(list(string), [])<br/>        essential    = optional(bool, false)<br/>        environment  = optional(map(string), {})<br/>        mount_points = optional(list(object({ name = string, path = string })), [])<br/>      })), [])<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the ECS Deployment | `string` | n/a | yes |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Common labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create VPC if vpc\_id is not provided | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Create a NAT gateway in the VPC (only when create\_vpc = true). Defaults false — Fargate tasks run in PUBLIC subnets with assign\_public\_ip (IGW egress), so the NAT (which only serves the unused private subnets) is pure cost. | `bool` | `false` | no |
| <a name="input_extra_ingress_ports"></a> [extra\_ingress\_ports](#input\_extra\_ingress\_ports) | Additional TCP ports to open on the created VPC's security group (only when create\_vpc = true). E.g. [9443] for a Hub multicluster uplink entrypoint fronted by an NLB. | `list(number)` | `[]` | no |
| <a name="input_otlp_gate_address"></a> [otlp\_gate\_address](#input\_otlp\_gate\_address) | OTLP collector base URL (e.g. https://collector.example.com). When set, an `otlp-collector-gate` sidecar blocks every task's main container from starting until that endpoint ACCEPTS an OTLP write — the Fargate form of cloud-init-snippets/otlp-collector-gate.sh.tpl, which every VM leg already runs. Empty disables the gate. Set it whenever the workload exports telemetry: a container that starts against a collector that is not up yet, or against a stale DNS record still pointing at a destroyed load balancer, stays dark — and terraform-side ordering cannot fix that. This gate FAILS CLOSED: the dependency is `SUCCESS`, so a gate that exhausts `otlp_gate_rounds` stops the task instead of releasing a workload that would report nothing. Do NOT set it on a container the collector's own existence depends on (see README). | `string` | `""` | no |
| <a name="input_otlp_gate_image"></a> [otlp\_gate\_image](#input\_otlp\_gate\_image) | Image the OTLP gate sidecar runs. Needs only a shell and curl — the workload images (Hub, whoami) are scratch, which is why the probe cannot live inside them. Defaults to an ECR Public image, NOT Docker Hub: anonymous Docker Hub pulls are rate-limited per source IP, every Fargate task in these demos egresses through one shared NAT gateway, and a gate that cannot pull is a task that never starts — a worse failure than the missing telemetry it prevents. The ACI twin hit exactly that with curlimages/curl (RegistryErrorResponse from index.docker.io, first try, 2026-08-11). | `string` | `"public.ecr.aws/amazonlinux/amazonlinux:2023"` | no |
| <a name="input_otlp_gate_rounds"></a> [otlp\_gate\_rounds](#input\_otlp\_gate\_rounds) | How many 10-second rounds the OTLP gate waits before giving up. Default 270 = 2700s = 45 minutes. Only meaningful when `otlp_gate_address` is set. The number to beat is 1800s: the SOA MINIMUM on traefik.ai, and therefore the longest a resolver may keep serving the NXDOMAIN it cached before dns-traefiker published the collector's record. The VM callers of the shared snippet pass 180 rounds — exactly 1800s, a budget with no margin by construction, expiring in the same breath as the cache it exists to outlast — and can only afford that because they ignore the result and boot anyway. This module cannot, because here exhaustion fails the task. 270 covers one full negative-cache window plus 900s: it absorbs the worst publication delay measured on aws-unified-ingress (record published 1350s after the task started, 2026-08-11) and leaves 1440s over the worst gate consumption actually observed (126/180 = 1260s on the aws-v6 run). It deliberately does NOT try to cover a second consecutive cache window — exhaustion restarts the task, each restart gets a fresh full budget, and ECS retries indefinitely, so the budget only has to cover the common worst case. A larger number would mostly delay the first signal that something is genuinely broken rather than merely slow. | `number` | `270` | no |
| <a name="input_otlp_gate_verify_tls"></a> [otlp\_gate\_verify\_tls](#input\_otlp\_gate\_verify\_tls) | Whether the OTLP gate VERIFIES the collector's certificate. Default true, and it must stay true wherever the gate is authoritative: `-k` is satisfied by any server that answers, including one still presenting Traefik's own self-signed cert during the ACME window, and including the PREVIOUS run's load balancer at a stale DNS record. The workload's OTel SDK verifies, so an unverified probe releases it into x509 failures it cannot recover from -- measured on the ACI twin 2026-08-11, where an insecure gate passed on its first attempt and the workload it released logged 62 consecutive `tls: failed to verify certificate` errors over the next five minutes. Set false ONLY if you point otlp\_gate\_image at an image with no CA bundle, where verification can never succeed and the gate would burn its whole budget; the default image (public.ecr.aws/amazonlinux/amazonlinux:2023) ships curl plus a 218KB bundle and verifies a public endpoint with no install step (checked 2026-08-12). | `bool` | `true` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs | `list(string)` | `[]` | no |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | IAM role ARN the task's containers assume (the task role — distinct from the execution role), e.g. so an in-task Traefik ECS provider can call the AWS ECS API. Empty = no task role. | `string` | `""` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for ECS resources | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_nlb_dns_names"></a> [nlb\_dns\_names](#output\_nlb\_dns\_names) | Map of service keys to their NLB DNS name (only services with nlb\_port set). The parent cluster dials https://<dns>:<nlb\_port>. |
| <a name="output_services"></a> [services](#output\_services) | Map of all ECS services with their details |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID the ECS services run in (created VPC, or the provided vpc\_id). |
<!-- END_TF_DOCS -->
