output "services" {
  description = "Map of all echo Cloud Run services with their details (uri is what the cloudRun provider routes to)"
  value = {
    for key, svc in google_cloud_run_v2_service.whoami : key => {
      id   = svc.id
      name = svc.name
      uri  = svc.uri
    }
  }
}

output "function_uri" {
  description = "HTTPS URI of the function's Cloud Run service (empty when enable_function = false)"
  value       = var.enable_function ? google_cloud_run_v2_service.function[0].uri : ""
}

output "function_service_name" {
  description = "Name of the function's Cloud Run service (empty when enable_function = false)"
  value       = var.enable_function ? google_cloud_run_v2_service.function[0].name : ""
}
