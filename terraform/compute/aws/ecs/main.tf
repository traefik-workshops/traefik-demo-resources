# Flatten clusters and apps into individual services
locals {
  # Create a flat list of services: [{cluster_name, app_name, config}, ...]
  services = flatten([
    for cluster_name, cluster_config in var.clusters : [
      for app_name, app_config in cluster_config.apps : {
        cluster_name       = cluster_name
        app_name           = app_name
        service_key        = "${cluster_name}-${app_name}"
        replicas           = app_config.replicas
        port               = app_config.port
        docker_image       = app_config.docker_image
        docker_command     = app_config.docker_command
        environment        = app_config.environment
        app_labels         = app_config.labels
        subnet_ids         = length(app_config.subnet_ids) > 0 ? app_config.subnet_ids : var.subnet_ids
        security_group_ids = length(app_config.security_group_ids) > 0 ? app_config.security_group_ids : var.security_group_ids
        assign_public_ip   = app_config.assign_public_ip
        nlb_port           = app_config.nlb_port
        nlb_internal       = app_config.nlb_internal
        volumes            = app_config.volumes
        mount_points       = app_config.mount_points
        depends_on         = app_config.depends_on
        sidecars           = app_config.sidecars
        health_check       = app_config.health_check
      }
    ]
  ])

  # --- the OTLP collector gate, container-native --------------------------------
  # EVERY VM leg in this library already waits for the collector before it starts
  # emitting: traefik/{ec2,gce,azure-vm,oci-vm,proxmox-vm,vsphere-vm,hyperv-vm,
  # morpheus-vm,alibaba-ecs} and apps/whoami/cloud-init all render
  # cloud-init-snippets/otlp-collector-gate.sh.tpl into first boot. The CONTAINER
  # legs never could: their images are scratch, there is no cloud-init, and so they
  # were the only legs that started exporting into the void. compute/azure/aci got
  # the container-native form in v6.1.9; this is the Fargate twin of it.
  #
  # Measured on aws-unified-ingress, 2026-08-11 -- the whoami-container tasks began
  # at 09:16:36 and posted to collector.aws.demo.traefik.ai for the next eleven
  # minutes without one export landing:
  #
  #   09:16:40  traces export: context deadline exceeded  (the name resolved, to the
  #             PREVIOUS run's ELB, which had already been destroyed)
  #   09:27:40  tls: failed to verify certificate: x509: certificate is valid for
  #             aedd0a91f861d756149469ebdebea953..., not collector.aws.demo.traefik.ai
  #
  # The whoami fork's OTel SDK is the exporter with no recovery path: pointed at a
  # dead endpoint at startup it stays dark, so that leg serves every request
  # perfectly and reports nothing -- routing tests pass straight over it and the
  # only symptom is a name missing from the service map.
  #
  # Terraform-side ordering does NOT fix this and cannot. observability/dns-gate
  # blocks on the NAME resolving, and a name resolves perfectly well while it still
  # points at the previous run's load balancer -- which is exactly the trace above.
  # An init container asks the only question that settles it, from inside the task's
  # own network: does this endpoint accept an OTLP write RIGHT NOW.
  #
  # This is a RUNTIME gate and nothing more: a non-essential sidecar plus
  # `dependsOn: SUCCESS`, rendered into the task definition. It adds NO terraform
  # edge, so it cannot deadlock an apply the way a module-level gate can. Every
  # caller here is safe to arm, including traefik/ecs, whose NLB the hub consumes as
  # its uplink address -- that NLB exists the moment terraform creates it, whether or
  # not any container ever starts.
  #
  # The one rule that does bind: the ADDRESS must be plan-known, built from the
  # domain. A computed address -- one read off an attribute of the thing the gate is
  # waiting for -- puts a real edge back into the graph and deadlocks with no cycle
  # error, which neither `validate` nor `graph` catches. That failure is real and is
  # why terraform/oci-ci gates at runtime instead; it is just not this mechanism.
  otlp_gate_enabled = var.otlp_gate_address != ""

  otlp_gate_script = local.otlp_gate_enabled ? templatefile(
    "${path.module}/../../../cloud-init-snippets/otlp-collector-gate.sh.tpl",
    { otlp_address = var.otlp_gate_address, rounds = var.otlp_gate_rounds }
  ) : ""

  # The snippet never calls `exit` -- on the VM legs it is pasted straight into a
  # cloud-init runcmd script, where an exit would abandon the rest of the boot -- so
  # it parks its verdict in $otlp_gate_status and lets each caller decide what
  # exhaustion means. THIS caller makes it fatal: `sh -c` exits with whatever its
  # last statement returns, so an exhausted gate exits non-zero and the SUCCESS
  # dependency below can never be satisfied.
  otlp_gate_command = local.otlp_gate_enabled ? ["/bin/sh", "-c", join("\n", [
    local.otlp_gate_script,
    "exit $otlp_gate_status",
  ])] : []

  # ECS runs a container marked non-essential to completion alongside the task, and
  # the dependency below is what holds the main container until it exits -- the same
  # ordering ACI gets from a native init_container. The gate image only has to carry
  # a shell and curl; the workload images here are scratch, which is why the probe
  # cannot live in the container it protects.
  otlp_gate_sidecars = local.otlp_gate_enabled ? [{
    name         = "otlp-collector-gate"
    image        = var.otlp_gate_image
    command      = local.otlp_gate_command
    essential    = false
    environment  = {}
    mount_points = []
  }] : []

  # SUCCESS, NOT COMPLETE -- and this reverses what this file used to say, so here is
  # the argument in full.
  #
  # COMPLETE only requires the gate to EXIT; SUCCESS requires it to exit ZERO (AWS:
  # "the same as COMPLETE, but it also requires that the container exits with a zero
  # status"). Under COMPLETE plus a gate that always exited 0, an exhausted gate
  # released the gateway anyway. That is failing OPEN: the exact outcome the gate was
  # built to prevent, arrived at silently, and indistinguishable in the task list from
  # a gate that worked.
  #
  # The old comment here argued the other way -- "a non-zero exit would make ECS treat
  # the task as failed and restart it forever, which is the wrong failure: 'runs,
  # reports late' beats 'never runs'." Two things were wrong with it.
  #
  # 1. "Reports late" was never on offer for THESE images. The whoami fork's SDK dials
  #    once at startup and never recovers; a released-but-dark task reports NEVER. The
  #    choice was never late-vs-never, it was never-and-invisible vs stopped-and-loud.
  #
  # 2. "Restart it forever" assumes a crash loop, and this cannot be one. Every failure
  #    path in the snippet walks the entire budget before returning -- a missing curl
  #    exits 127 just as slowly as a dead endpoint times out -- so one attempt costs
  #    otlp_gate_rounds x 10s (45 minutes at the default). On top of that the ECS
  #    service scheduler throttles tasks that stop without ever reaching RUNNING,
  #    stretching the gap between launches to a documented maximum of 27 minutes and
  #    emitting `(service X) is unable to consistently start tasks successfully`. The
  #    steady state is therefore roughly one task launch per 45-72 minutes, visible in
  #    the service events -- not a hot loop, and a rounding error against the NAT and
  #    load balancer this demo is already paying for.
  #
  # What the restart does and does NOT buy. It does not flush any DNS cache: the loop
  # already re-resolves every 10 seconds, and the NXDOMAIN that starts this whole
  # problem is cached in the VPC resolver, which is shared and outlives the task. What
  # a restart buys is a fresh full budget and, above all, a gateway that never starts
  # exporting into a void. Retries continue indefinitely, so the moment the collector
  # does answer, the next attempt releases the gateway and the service converges with
  # nobody touching it.
  #
  # The apply is not affected either way: aws_ecs_service does not wait for steady
  # state here, so exhaustion surfaces as a service stuck below its desired count with
  # that event attached -- loud, attributable, and cheap to read -- rather than as a
  # green terraform run over a demo that quietly reports nothing.
  otlp_gate_depends_on = local.otlp_gate_enabled ? [{
    name      = "otlp-collector-gate"
    condition = "SUCCESS"
  }] : []

  # Convert to map for for_each with global index for even distribution
  services_map = {
    for idx, svc in local.services : svc.service_key => merge(svc, {
      idx        = idx
      subnet_ids = [for i in range(length(svc.subnet_ids)) : svc.subnet_ids[(idx + i) % length(svc.subnet_ids)]]
      # Appended, never replacing: traefik/ecs already ships a config-init sidecar the
      # main container depends on, and dropping that would leave Traefik with no
      # dynamic configuration at all.
      #
      # The gate lands LAST in the dependency list, which used to matter: agents
      # before 1.44.4 (and again before 1.61.2) returned on the first unresolved
      # dependency instead of checking the rest, so a failing SUCCESS dependency
      # listed after an unresolved one left the task PENDING forever instead of
      # stopping it (aws/amazon-ecs-agent#2579). Fargate's managed agent is long past
      # both fixes, and the dependency ahead of the gate here is a config-init that
      # exits within seconds regardless -- but that is why the order is not arbitrary.
      sidecars   = concat(svc.sidecars, local.otlp_gate_sidecars)
      depends_on = concat(svc.depends_on, local.otlp_gate_depends_on)
    })
  }

  # Get unique cluster names
  cluster_names = distinct([for svc in local.services : svc.cluster_name])

  # Services fronted by an NLB (stable public address on nlb_port).
  nlb_services = { for k, s in local.services_map : k => s if s.nlb_port != null }
}

module "vpc" {
  count  = var.create_vpc ? 1 : 0
  source = "../vpc"

  name                = "ecs-vpc"
  cidr                = "10.0.0.0/16"
  public_subnets      = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  extra_ingress_ports = var.extra_ingress_ports
  enable_nat_gateway  = var.enable_nat_gateway
}

data "aws_region" "current" {}

# Create ECS clusters
resource "aws_ecs_cluster" "cluster" {
  for_each = toset(local.cluster_names)

  name = each.value
}

# CloudWatch logs per service (Fargate has no SSH — this is the only window into
# the containers; the execution role's AmazonECSTaskExecutionRolePolicy grants the
# log writes).
resource "aws_cloudwatch_log_group" "service" {
  for_each = local.services_map

  name              = "/ecs/${var.name}/${each.value.cluster_name}-${each.value.app_name}"
  retention_in_days = 7
}

# Create IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create ECS task definitions. Each task is the main container + any sidecars
# (e.g. a config-init that writes dynamic config into a shared volume, or a
# co-located backend reachable on localhost).
resource "aws_ecs_task_definition" "service" {
  for_each = local.services_map

  family                   = "${each.value.cluster_name}-${each.value.app_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  # Task role (optional): the identity the containers assume to call AWS APIs — e.g.
  # an in-task Traefik ECS provider listing tasks. Distinct from the execution role.
  task_role_arn = var.task_role_arn != "" ? var.task_role_arn : null
  cpu           = "1024"
  memory        = "2048"

  dynamic "volume" {
    for_each = toset(each.value.volumes)
    content {
      name = volume.value
    }
  }

  container_definitions = jsonencode(concat(
    [
      merge(
        {
          name         = each.value.app_name
          image        = each.value.docker_image
          essential    = true
          portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]
          dockerLabels = merge(var.common_labels, each.value.app_labels)
          mountPoints  = [for m in each.value.mount_points : { sourceVolume = m.name, containerPath = m.path }]
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.service[each.key].name
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = each.value.app_name
            }
          }
        },
        each.value.docker_command != "" ? { command = split(" ", each.value.docker_command) } : {},
        length(each.value.environment) > 0 ? {
          environment = [for k, v in each.value.environment : { name = k, value = v }]
        } : {},
        length(each.value.depends_on) > 0 ? {
          dependsOn = [for d in each.value.depends_on : { containerName = d.name, condition = d.condition }]
        } : {},
        each.value.health_check != null ? {
          healthCheck = {
            command     = each.value.health_check.command
            interval    = each.value.health_check.interval
            timeout     = each.value.health_check.timeout
            retries     = each.value.health_check.retries
            startPeriod = each.value.health_check.start_period
          }
        } : {}
      )
    ],
    [
      for sc in each.value.sidecars : merge(
        {
          name        = sc.name
          image       = sc.image
          essential   = sc.essential
          mountPoints = [for m in sc.mount_points : { sourceVolume = m.name, containerPath = m.path }]
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.service[each.key].name
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = sc.name
            }
          }
        },
        length(sc.command) > 0 ? { command = sc.command } : {},
        length(sc.environment) > 0 ? {
          environment = [for k, v in sc.environment : { name = k, value = v }]
        } : {}
      )
    ]
  ))
}

# --- Optional NLB per service: a stable internet-facing address on nlb_port
# (the Fargate-equivalent of an EC2 Elastic IP) forwarding to the task's port.
resource "aws_lb" "nlb" {
  for_each = local.nlb_services

  name               = substr("${each.value.cluster_name}-${each.value.app_name}-nlb", 0, 32)
  load_balancer_type = "network"
  internal           = each.value.nlb_internal
  subnets            = var.create_vpc ? module.vpc[0].public_subnet_ids : each.value.subnet_ids
}

resource "aws_lb_target_group" "nlb" {
  for_each = local.nlb_services

  name        = substr("${each.value.cluster_name}-${each.value.app_name}-tg", 0, 32)
  port        = each.value.nlb_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
}

resource "aws_lb_listener" "nlb" {
  for_each = local.nlb_services

  load_balancer_arn = aws_lb.nlb[each.key].arn
  port              = each.value.nlb_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb[each.key].arn
  }
}

# Create ECS services
resource "aws_ecs_service" "service" {
  for_each = local.services_map

  name            = each.value.app_name
  cluster         = aws_ecs_cluster.cluster[each.value.cluster_name].id
  task_definition = aws_ecs_task_definition.service[each.key].arn
  desired_count   = each.value.replicas
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.create_vpc ? module.vpc[0].public_subnet_ids : each.value.subnet_ids
    security_groups  = var.create_vpc ? module.vpc[0].security_group_ids : each.value.security_group_ids
    assign_public_ip = each.value.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = each.value.nlb_port != null ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.nlb[each.key].arn
      container_name   = each.value.app_name
      container_port   = each.value.port
    }
  }

  depends_on = [aws_lb_listener.nlb]
}
