# whoami on IBM Cloud Code Engine — the serverless IBM sibling of
# apps/whoami/cloudrun and apps/whoami/aci. Each app is one Code Engine app in
# a project (module-created by default). Code Engine pulls public Docker Hub
# images directly, so no registry mirror is needed (unlike Cloud Run).
#
# NO traefik config surface exists here — Code Engine apps have no
# user-settable labels or annotations, so the Hub ibmCodeEngine provider is
# CONFIG-LESS: every ready app becomes a service at its endpoint URL, routed
# by the provider's defaultRule; constraints match only the synthesized
# pseudo-labels `name` and `visibility`.

data "ibm_resource_group" "default" {
  count = var.enable_project && var.resource_group_id == "" ? 1 : 0

  is_default = true
}

resource "ibm_code_engine_project" "whoami" {
  count = var.enable_project ? 1 : 0

  name              = var.project_name
  resource_group_id = var.resource_group_id != "" ? var.resource_group_id : data.ibm_resource_group.default[0].id
}

locals {
  project_id = var.enable_project ? ibm_code_engine_project.whoami[0].project_id : var.project_id

  # A tag is a `:` in the LAST path segment (a registry host may carry a :port).
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"
}

resource "ibm_code_engine_app" "whoami" {
  for_each = var.apps

  project_id      = local.project_id
  name            = each.key
  image_reference = local.image

  # Code Engine routes the endpoint to image_port; WHOAMI_PORT_NUMBER (below)
  # makes whoami actually bind it.
  image_port = try(each.value.port, 80)

  # local_public = project-local + public endpoint; the discovery provider's
  # synthesized `visibility` pseudo-label reflects it.
  managed_domain_mappings = var.managed_domain_mappings

  # min 1 keeps an instance ready at all times so the ibmCodeEngine provider
  # (which only routes READY apps) always discovers it.
  scale_min_instances = var.min_scale
  scale_max_instances = var.max_scale

  # Built-ins first so module/per-app `environment` wins on collision.
  dynamic "run_env_variables" {
    for_each = merge(
      {
        WHOAMI_PORT_NUMBER = tostring(try(each.value.port, 80))
        WHOAMI_NAME        = try(each.value.name, each.key)
      },
      var.environment,
      try(each.value.environment, {}),
    )

    content {
      type  = "literal"
      name  = run_env_variables.key
      value = run_env_variables.value
    }
  }

  lifecycle {
    precondition {
      condition     = var.enable_project || var.project_id != ""
      error_message = "project_id must be provided when enable_project is false."
    }
  }
}
