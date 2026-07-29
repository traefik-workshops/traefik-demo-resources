locals {
  clusters = {
    for cluster_name, cluster_config in var.clusters : cluster_name => merge(
      cluster_config,
      {
        apps = {
          # Strip `name` before passing on (compute/aws/ecs's apps object is strictly
          # typed and has no `name`); it only feeds WHOAMI_NAME, so whoami's body shows
          # `Name: <name>` (e.g. whoami-ecs). Defaults to the app key.
          for app_name, app_config in cluster_config.apps : app_name => merge(
            { for k, v in app_config : k => v if k != "name" },
            {
              docker_image       = var.whoami_image
              docker_command     = "--verbose"
              subnet_ids         = cluster_config.subnet_ids
              security_group_ids = cluster_config.security_group_ids
              # Built-in WHOAMI_NAME first so module/per-app env can override it.
              environment = merge(
                { WHOAMI_NAME = try(app_config.name, app_name) },
                var.environment,
                try(app_config.environment, {}),
              )
              # Every whoami task self-reports health: the image is FROM scratch so
              # the check execs the binary's own -health-check self-probe (GET its
              # /health over loopback). Discovering Traefiks run healthyTasksOnly,
              # and a task with NO check is HealthStatus=UNKNOWN -> filtered out —
              # so this default is load-bearing, not cosmetic. Per-app override wins.
              health_check = try(app_config.health_check, {
                command = ["CMD", "/whoami", "-health-check"]
              })
            }
          )
        }
      }
    )
  }
}

module "echo_services" {
  source = "../../../compute/aws/ecs"

  name               = var.name
  clusters           = local.clusters
  create_vpc         = var.create_vpc
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  common_labels      = var.common_labels
}
