output "project_id" {
  description = "Code Engine project ID (GUID) the apps run in — feed it to the ibmCodeEngine provider's projectID"
  value       = local.project_id
}

output "apps" {
  description = "Map of all echo server apps with their details"
  value = {
    for key, app in ibm_code_engine_app.whoami : key => {
      id                = app.app_id
      name              = app.name
      endpoint          = app.endpoint
      endpoint_internal = app.endpoint_internal
    }
  }
}
