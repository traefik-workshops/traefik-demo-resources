variable "name" {
  description = "Name of the ECS Deployment"
  type        = string
}

variable "clusters" {
  description = "Map of ECS clusters with their applications"
  type = map(object({
    apps = map(object({
      replicas           = optional(number, 1)
      subnet_ids         = optional(list(string), [])
      port               = optional(number, 80)
      docker_image       = optional(string, "traefik/whoami:latest")
      docker_command     = optional(string, "")
      labels             = optional(map(string), {})
      environment        = optional(map(string), {})
      security_group_ids = optional(list(string), [])

      # Fargate task needs egress to pull images; set true (the module places
      # tasks in public subnets) unless a NAT-routed private subnet is supplied.
      assign_public_ip = optional(bool, false)

      # If set, front the task with an NLB on this port (a stable address — the
      # Fargate-equivalent of an EC2 Elastic IP). Targets the task's `port`.
      nlb_port = optional(number, null)

      # Make that NLB internal (private IPs only) instead of internet-facing — for a
      # parent that dials the spoke privately within a shared VPC. Needs private
      # (NAT-routed) subnet_ids + assign_public_ip = false.
      nlb_internal = optional(bool, false)

      # Ephemeral task volumes (names) + the main container's mounts, for delivering
      # config files into a scratch image (e.g. a config-init sidecar writes them).
      volumes      = optional(list(string), [])
      mount_points = optional(list(object({ name = string, path = string })), [])

      # Container start ordering, e.g. wait for a config-init sidecar to COMPLETE.
      depends_on = optional(list(object({
        name      = string
        condition = optional(string, "START") # START | COMPLETE | SUCCESS | HEALTHY
      })), [])

      # ECS container health check, exec'd INSIDE the container. Required when the
      # discovering Traefik runs with healthyTasksOnly=true: a task with no health
      # check reports HealthStatus=UNKNOWN and is filtered out, emptying the service.
      # Scratch images have no curl — the whoami fork ships a self-probe for this
      # (command = ["CMD", "/whoami", "-health-check"]).
      health_check = optional(object({
        command      = list(string)
        interval     = optional(number, 10) # seconds between probes
        timeout      = optional(number, 5)
        retries      = optional(number, 3)
        start_period = optional(number, 15) # grace before failures count
      }), null)

      # Extra containers in the same task (sidecars: config writers, co-located
      # backends reachable on localhost, etc.).
      sidecars = optional(list(object({
        name         = string
        image        = string
        command      = optional(list(string), [])
        essential    = optional(bool, false)
        environment  = optional(map(string), {})
        mount_points = optional(list(object({ name = string, path = string })), [])
      })), [])
    }))
  }))
}

variable "extra_ingress_ports" {
  description = "Additional TCP ports to open on the created VPC's security group (only when create_vpc = true). E.g. [9443] for a Hub multicluster uplink entrypoint fronted by an NLB."
  type        = list(number)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway in the VPC (only when create_vpc = true). Defaults false — Fargate tasks run in PUBLIC subnets with assign_public_ip (IGW egress), so the NAT (which only serves the unused private subnets) is pure cost."
  type        = bool
  default     = false
}

variable "create_vpc" {
  description = "Create VPC if vpc_id is not provided"
  type        = bool
  default     = true
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID for ECS resources"
  type        = string
  default     = ""

  validation {
    condition     = var.create_vpc || var.vpc_id != ""
    error_message = "vpc_id must be provided if create_vpc is false"
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.subnet_ids) != 0
    error_message = "subnet_ids must be provided if create_vpc is false"
  }
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.security_group_ids) != 0
    error_message = "security_group_ids must be provided if create_vpc is false"
  }
}

variable "task_role_arn" {
  description = "IAM role ARN the task's containers assume (the task role — distinct from the execution role), e.g. so an in-task Traefik ECS provider can call the AWS ECS API. Empty = no task role."
  type        = string
  default     = ""
}

variable "otlp_gate_address" {
  description = "OTLP collector base URL (e.g. https://collector.example.com). When set, an `otlp-collector-gate` sidecar blocks every task's main container from starting until that endpoint ACCEPTS an OTLP write — the Fargate form of cloud-init-snippets/otlp-collector-gate.sh.tpl, which every VM leg already runs. Empty disables the gate. Set it whenever the workload exports telemetry: a container that starts against a collector that is not up yet, or against a stale DNS record still pointing at a destroyed load balancer, stays dark — and terraform-side ordering cannot fix that. This gate FAILS CLOSED: the dependency is `SUCCESS`, so a gate that exhausts `otlp_gate_rounds` stops the task instead of releasing a workload that would report nothing. Do NOT set it on a container the collector's own existence depends on (see README)."
  type        = string
  default     = ""
}

variable "otlp_gate_rounds" {
  description = "How many 10-second rounds the OTLP gate waits before giving up. Default 270 = 2700s = 45 minutes. Only meaningful when `otlp_gate_address` is set. The number to beat is 1800s: the SOA MINIMUM on traefik.ai, and therefore the longest a resolver may keep serving the NXDOMAIN it cached before dns-traefiker published the collector's record. The VM callers of the shared snippet pass 180 rounds — exactly 1800s, a budget with no margin by construction, expiring in the same breath as the cache it exists to outlast — and can only afford that because they ignore the result and boot anyway. This module cannot, because here exhaustion fails the task. 270 covers one full negative-cache window plus 900s: it absorbs the worst publication delay measured on aws-unified-ingress (record published 1350s after the task started, 2026-08-11) and leaves 1440s over the worst gate consumption actually observed (126/180 = 1260s on the aws-v6 run). It deliberately does NOT try to cover a second consecutive cache window — exhaustion restarts the task, each restart gets a fresh full budget, and ECS retries indefinitely, so the budget only has to cover the common worst case. A larger number would mostly delay the first signal that something is genuinely broken rather than merely slow."
  type        = number
  default     = 270
}

variable "otlp_gate_image" {
  description = "Image the OTLP gate sidecar runs. Needs only a shell and curl — the workload images (Hub, whoami) are scratch, which is why the probe cannot live inside them. Defaults to an ECR Public image, NOT Docker Hub: anonymous Docker Hub pulls are rate-limited per source IP, every Fargate task in these demos egresses through one shared NAT gateway, and a gate that cannot pull is a task that never starts — a worse failure than the missing telemetry it prevents. The ACI twin hit exactly that with curlimages/curl (RegistryErrorResponse from index.docker.io, first try, 2026-08-11)."
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux:2023"
}
