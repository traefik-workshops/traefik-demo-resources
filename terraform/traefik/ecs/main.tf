# =============================================================================
# ECS Traefik Deployment
# =============================================================================
# Uses extracted config from traefik/shared module (via Helm template).
# =============================================================================

locals {
  # Use extracted CLI arguments from Helm template
  # Uses centralized filtering to exclude Kubernetes-specific args
  traefik_arguments = module.config.extracted_cli_args_cloud

  # Use shared module for image reference
  traefik_image = module.config.image_full

  # Build Docker labels including ports
  docker_labels = merge(var.extra_labels, {
    for name, port in module.config.ports :
    "traefik.http.routers.${name}.entrypoints" => name
    if try(port.expose.default, false)
    },
    # Self-register the Traefik task's own dashboard via its ECS provider (-> dashboard@ecs).
    # Disable when the dashboard is advertised another way (e.g. a file-rule uplink): without
    # traefik.enable the task isn't self-discovered at all, so no redundant self-router appears.
    var.enable_dashboard_discovery ? {
      "traefik.enable"                                           = "true"
      "traefik.http.routers.dashboard.rule"                      = module.config.dashboard_match_rule
      "traefik.http.routers.dashboard.entrypoints"               = module.config.dashboard_entrypoints[0]
      "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
  } : {})
}

module "ecs" {
  source = "../../compute/aws/ecs"

  name                = "traefik"
  extra_ingress_ports = var.extra_ingress_ports

  # GATED, as of 2026-08-11. This comment previously forbade the gate on two grounds;
  # a live measurement refuted one and the other conflated two different mechanisms.
  # The history is kept because the distinction it gets wrong is subtle and expensive.
  #
  # WHAT WAS MEASURED. aws-unified-ingress, 2026-08-11: ECS task up 14:50:29, the
  # collector's DNS record published 15:13, and at 15:29:09 the gateway was STILL
  # logging `lookup collector.<domain> on 10.0.0.2:53: no such host` — 39 minutes dark
  # while all 15 acts passed. A forced restart closed the service map inside a minute.
  #
  # WHY "the exporters recover on their own" IS NOT A DEFENCE. They do retry, and on
  # azure-unified-ingress the ACI twin genuinely did recover. The difference is not the
  # exporter, it is DNS: 10.0.0.2 is the VPC resolver, the first lookup lands before the
  # record exists, and NXDOMAIN is NEGATIVELY CACHED for the zone's SOA MINIMUM — 1800s
  # on traefik.ai. Every retry inside that window asks the cache, not the authority, so
  # the retry loop cannot save a leg that asked too early. Whether a run recovers is
  # therefore a race, and "it recovered on the cloud I happened to test" is exactly the
  # evidence that makes a race look like a rule.
  #
  # WHY IT DOES NOT DEADLOCK. The old text collapsed two unrelated things. The TERRAFORM
  # deadlock was real: at v1.3.3 observability/dns-gate sat upstream of this module and
  # waited for a record whose publication it was itself blocking, so only a STALE record
  # from a previous run ever let an apply through. `otlp_gate_address` is not that. It
  # renders a NON-ESSENTIAL SIDECAR into the task definition with `dependsOn: COMPLETE`;
  # it adds no module edge, and the NLB — which is what the hub consumes as its uplink
  # address — exists the moment terraform creates it, whether or not any container ever
  # starts. So the hub still gets its address, still comes up, and still brings up the
  # collector the gate is waiting for. Nothing waits on itself.
  #
  # The gate also exits 0 on timeout by design, so the worst case it can produce is a
  # gateway that starts late and reports late — never a task that never runs.
  #
  # ONE CONSTRAINT, and it is the whole reason this is safe: otlp_gate_address must be
  # PLAN-KNOWN, i.e. built from the domain, never read off an attribute of the hub. A
  # computed address would put a real edge back into the graph and reintroduce the
  # deadlock this comment spent five years' worth of debugging learning to avoid.
  otlp_gate_address = var.otlp_gate_address

  clusters = {
    traefik = {
      apps = {
        traefik = {
          replicas         = module.config.replica_count
          port             = coalesce(var.nlb_port, 80)
          nlb_port         = var.nlb_port
          nlb_internal     = var.nlb_internal
          assign_public_ip = var.assign_public_ip
          docker_image     = local.traefik_image
          # The shared module strips --hub.token from the extracted args so it can be
          # injected per-platform. The Hub binary reads the FLAG (EC2's systemd does
          # `--hub.token=$HUB_TOKEN`); ECS commands are exec'd with no shell, so the
          # value is inlined here rather than referenced from an env var.
          docker_command     = join(" ", concat(["--hub.token=${var.traefik_hub_token}"], local.traefik_arguments))
          subnet_ids         = var.subnet_ids
          security_group_ids = var.security_group_ids
          labels             = local.docker_labels

          # custom_envs reached module.config and then went NOWHERE: its env_vars_list
          # output had no consumer here, so the task definition rendered
          # "environment": [] and every caller's custom_envs was silently dropped. The
          # EC2 sibling wires this correctly (traefik/ec2/main.tf:17,55) -- ECS was missed.
          #
          # Live proof, aws-unified-ingress 2026-08-11: traefik-container was the ONLY
          # service in Tempo whose spans lacked resource.cloud.provider, while
          # traefik-hub, traefik-vm, whoami-vm and whoami-container all carried it.
          # Invisible to routing tests, which is exactly why 15/15 passed over it.
          environment = { for e in var.custom_envs : e.name => e.value }

          # The Hub image is scratch (no shell/cloud-init), so a config-init sidecar
          # writes the file-provider config into a shared volume Traefik mounts.
          volumes      = var.file_provider_config != "" ? ["dynamic"] : []
          mount_points = var.file_provider_config != "" ? [{ name = "dynamic", path = var.file_provider_path }] : []
          depends_on   = var.file_provider_config != "" ? [{ name = "config-init", condition = "COMPLETE" }] : []

          sidecars = concat(
            var.file_provider_config != "" ? [{
              name         = "config-init"
              image        = "busybox:1.38.0"
              essential    = false
              command      = ["sh", "-c", "echo \"$DYNAMIC_B64\" | base64 -d > ${var.file_provider_path}/dynamic.yml"]
              environment  = { DYNAMIC_B64 = base64encode(var.file_provider_config) }
              mount_points = [{ name = "dynamic", path = var.file_provider_path }]
            }] : [],
            var.colocated_backend_image != "" ? [{
              name      = "backend"
              image     = var.colocated_backend_image
              essential = true
              # Keep the backend off :80 — Traefik's web entrypoint owns it in the
              # task's shared awsvpc network namespace.
              command = var.colocated_backend_port != 80 ? ["--port", tostring(var.colocated_backend_port)] : []
            }] : []
          )
        }
      }
    }
  }

  create_vpc = var.create_vpc
  vpc_id     = var.vpc_id
  # Plumb subnet_ids/security_group_ids to the compute module's TOP LEVEL too (not
  # just per-app above) — that's where the create_vpc=false validation checks them.
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  task_role_arn      = var.task_role_arn
}

# =============================================================================
# Shared Configuration Module - ECS
# =============================================================================
# ECS uses extracted config from helm template (extract_config=true).
# Shared variables are defined here alongside the module instantiation.
# =============================================================================

module "config" {
  source = "../shared"

  # Extract config - ECS needs CLI args, env vars from Helm template
  extract_config = true

  # Feature Flags
  enable_api_gateway    = var.enable_api_gateway
  enable_ai_gateway     = var.enable_ai_gateway
  enable_mcp_gateway    = var.enable_mcp_gateway
  enable_api_management = false # K8s only
  enable_offline_mode   = var.enable_offline_mode
  enable_preview_mode   = var.enable_preview_mode
  enable_debug          = var.enable_debug

  # Replica count
  replica_count = var.replica_count

  # Versions & Images
  traefik_chart_version   = var.traefik_chart_version
  traefik_tag             = var.traefik_tag
  traefik_hub_tag         = var.traefik_hub_tag
  traefik_hub_preview_tag = var.traefik_hub_preview_tag
  custom_image_registry   = var.custom_image_registry
  custom_image_repository = var.custom_image_repository
  custom_image_tag        = var.custom_image_tag

  # Observability
  log_level                    = var.log_level
  otlp_address                 = var.otlp_address
  otlp_service_name            = var.otlp_service_name
  enable_otlp_access_logs      = var.enable_otlp_access_logs
  enable_otlp_application_logs = var.enable_otlp_application_logs
  enable_otlp_metrics          = var.enable_otlp_metrics
  enable_otlp_traces           = var.enable_otlp_traces
  enable_prometheus            = var.enable_prometheus
  enable_access_logs           = var.enable_access_logs

  # Plugins & Extensions
  custom_plugins       = var.custom_plugins
  custom_ports         = var.custom_ports
  custom_arguments     = var.custom_arguments
  custom_envs          = var.custom_envs
  file_provider_config = var.file_provider_config
  file_provider_path   = var.file_provider_path

  # Licensing & DNS
  traefik_hub_token      = var.traefik_hub_token
  cloudflare_dns         = var.cloudflare_dns
  is_staging_letsencrypt = var.is_staging_letsencrypt

  # Dashboard
  enable_dashboard      = var.enable_dashboard
  dashboard_insecure    = var.dashboard_insecure
  dashboard_entrypoints = var.dashboard_entrypoints
  dashboard_match_rule  = var.dashboard_match_rule

  # Providers
  multicluster_provider = var.multicluster_provider
  nutanix_provider      = var.nutanix_provider
}
