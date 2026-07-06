variable "apps" {
  description = "Map of Cloud Run services to deploy. Workload config is `annotations` (dotted traefik.* keys, the cloudRun provider's config source); optional `labels` (dotless) feed provider constraints only; optional `environment` (map) is merged over the module-level `environment` into the container. No replicas — Cloud Run scales via min/max instances. { name = { port, name, environment, annotations, labels } }."
  type        = any
  default     = {}
}

variable "location" {
  description = "Cloud Run region (also used for the Artifact Registry repositories and the function source bucket)"
  type        = string
  default     = "us-central1"
}

variable "whoami_image" {
  description = "Whoami image every service runs, pulled through the module's Docker Hub mirror — so it must be a docker.io reference (Cloud Run can't pull docker.io directly; use `image` for other registries). Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/zalbiraw/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables added to every whoami container, e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "image" {
  description = "Full image reference override. Empty = pull whoami_image through the module's Docker Hub mirror (requires enable_registry_mirror). Must be an Artifact Registry / GCR path — Cloud Run can't pull docker.io directly."
  type        = string
  default     = ""
}

variable "enable_registry_mirror" {
  description = "Create an Artifact Registry REMOTE repository mirroring Docker Hub (how whoami_image becomes pullable by Cloud Run). Disable only when `image` is set."
  type        = bool
  default     = true
}

variable "mirror_repository_id" {
  description = "Repository ID for the Docker Hub mirror (unique per project+location)"
  type        = string
  default     = "dockerhub-mirror"
}

variable "ingress" {
  description = "Cloud Run ingress setting (INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER). The Traefik child dials the public service URL, so ALL is the demo default."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
}

variable "min_instances" {
  description = "Minimum instance count per service (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum instance count per service"
  type        = number
  default     = 2
}

variable "enable_unauthenticated" {
  description = "Grant roles/run.invoker to allUsers on every service (demo-grade; the Traefik child dials the service URL unauthenticated)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Cloud Run v2 deletion protection. Off — demos are torn down per-run."
  type        = bool
  default     = false
}

variable "common_annotations" {
  description = "Annotations applied to every service (dotted traefik.* keys allowed — provider workload config)"
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Labels applied to every service (dotless — provider constraints only)"
  type        = map(string)
  default     = {}
}

variable "enable_function" {
  description = "Also deploy a second 'function' Cloud Run service (a gen2 Cloud Function IS a Cloud Run service, discovered via the same annotations pathway). It runs the same whoami image as the plain services — terraform's build_config source build never persists (the Cloud Run API drops it), so a from-source build isn't reliable."
  type        = bool
  default     = false
}

variable "function_name" {
  description = "Name of the function's Cloud Run service (also its WHOAMI_NAME, so the body reports Name: <function_name>)"
  type        = string
  default     = "whoami-fn"
}

variable "function_port" {
  description = "Container port the function's whoami binds (via WHOAMI_PORT_NUMBER — whoami ignores Cloud Run's $PORT)."
  type        = number
  default     = 80
}

variable "function_annotations" {
  description = "Annotations for the function's Cloud Run service (dotted traefik.* keys — same pathway as the plain services)"
  type        = map(string)
  default     = {}
}

variable "function_labels" {
  description = "Labels for the function's Cloud Run service (dotless — provider constraints only)"
  type        = map(string)
  default     = {}
}

variable "function_environment" {
  description = "Extra env for the function's whoami container, merged last (e.g. its own OTEL_SERVICE_NAME so it ships telemetry under a distinct name)."
  type        = map(string)
  default     = {}
}
