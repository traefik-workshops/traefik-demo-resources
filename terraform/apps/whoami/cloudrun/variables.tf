variable "apps" {
  description = "Map of Cloud Run services to deploy. Workload config is `annotations` (dotted traefik.* keys, the cloudRun provider's config source); optional `labels` (dotless) feed provider constraints only. No replicas — Cloud Run scales via min/max instances. { name = { port, name, annotations, labels } }."
  type        = any
  default     = {}
}

variable "location" {
  description = "Cloud Run region (also used for the Artifact Registry repositories and the function source bucket)"
  type        = string
  default     = "us-central1"
}

variable "whoami_version" {
  description = "The traefik/whoami image tag to run — they carry a `v` prefix (e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "image" {
  description = "Full image reference override. Empty = pull traefik/whoami through the module's Docker Hub mirror (requires enable_registry_mirror). Must be an Artifact Registry / GCR path — Cloud Run can't pull docker.io directly."
  type        = string
  default     = ""
}

variable "enable_registry_mirror" {
  description = "Create an Artifact Registry REMOTE repository mirroring Docker Hub (how traefik/whoami becomes pullable by Cloud Run). Disable only when `image` is set."
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
  description = "Also deploy a whoami-ish HTTP function from inline source via Cloud Run's build_config (the gen2 Cloud Functions path — the built function IS a Cloud Run service, discovered via the same annotations pathway). Requires the Cloud Build API."
  type        = bool
  default     = false
}

variable "function_name" {
  description = "Name of the function's Cloud Run service (also prefixes its source bucket, image repository, and build SA)"
  type        = string
  default     = "whoami-fn"
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
