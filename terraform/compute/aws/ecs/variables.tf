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
