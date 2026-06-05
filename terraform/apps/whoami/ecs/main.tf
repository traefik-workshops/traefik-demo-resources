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
              docker_image       = "traefik/whoami:latest"
              subnet_ids         = cluster_config.subnet_ids
              security_group_ids = cluster_config.security_group_ids
              environment = {
                WHOAMI_NAME = try(app_config.name, app_name)
              }
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
