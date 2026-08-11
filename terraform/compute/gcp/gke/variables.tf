variable "gke_version" {
  type        = string
  default     = ""
  description = "GKE cluster version."
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name."
}

variable "cluster_location" {
  type        = string
  default     = "us-west1-a"
  description = "GKE cluster location."
}

variable "cluster_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes for the cluster."
}

variable "cluster_node_type" {
  type        = string
  default     = "e2-standard-2"
  description = "Default machine type for cluster"
}

variable "enable_workload_identity" {
  type        = bool
  default     = false
  description = "Enable GKE Workload Identity: sets the cluster workload pool (<project>.svc.id.goog) and GKE_METADATA mode on every node pool, so pods get keyless GCP credentials via annotated ServiceAccounts."
}

variable "enable_gpu" {
  type        = bool
  default     = false
  description = "Enable GPU node pool"
}

variable "gpu_type" {
  type        = string
  default     = "nvidia-l4"
  description = "GPU type"
}

variable "gpu_count" {
  type        = number
  default     = 1
  description = "GPU count"
}

variable "gpu_node_type" {
  type        = string
  default     = "g2-standard-8"
  description = "GPU node type"
}

variable "gpu_node_count" {
  type        = number
  default     = 1
  description = "GPU node count"
}

variable "worker_nodes" {
  type = list(object({
    label = string
    taint = string
    count = number
  }))
  default     = []
  description = "Worker node pool definitions. Each entry creates a dedicated node pool with the given label and taint."
}

variable "update_kubeconfig" {
  type        = bool
  default     = true
  description = "Update kubeconfig after cluster creation"
}

# `gcloud container clusters get-credentials` writes a kubeconfig user whose exec block
# invokes gke-gcloud-auth-plugin with NO env, so the plugin inherits whatever gcloud
# configuration the CALLER happens to have. That makes the context only as good as the
# ambient environment: a caller who activated a service account in an isolated
# CLOUDSDK_CONFIG for the apply produces a context that silently falls back to the
# operator's own (possibly lapsed) login the moment anything else runs kubectl.
#
# Anything set here is written into users[].user.exec.env, so the context carries its own
# authentication environment and works for any caller. Deliberately a free-form map: the
# module stays generic and the caller owns the path.
variable "kubeconfig_exec_env" {
  type        = map(string)
  default     = {}
  description = "Environment variables pinned into the kubeconfig user's exec block (e.g. CLOUDSDK_CONFIG), so kubectl against this context does not depend on the caller's ambient gcloud configuration. Requires update_kubeconfig."
}
