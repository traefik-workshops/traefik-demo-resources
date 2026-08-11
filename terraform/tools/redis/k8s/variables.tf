variable "name" {
  description = "The name of the redis release"
  type        = string
  default     = "traefik"
}

variable "namespace" {
  description = "Namespace for the Redis deployment"
  type        = string
}

variable "password" {
  description = "Redis password. DEMO DEFAULT — override per environment."
  type        = string
  default     = "topsecretpassword"
  sensitive   = true
}

variable "replica_count" {
  description = "Number of replicas for the Redis deployment"
  type        = number
  default     = 1
}

variable "persistence" {
  description = "Back Redis's /data with a PersistentVolumeClaim (8Gi RWO) instead of emptyDir. Default FALSE — see the note in main.tf: the claim becomes a real cloud disk that survives `terraform destroy` (this chart even retains it when the StatefulSet goes), and nothing this Redis holds is worth one. It is NOT the ACME store — Hub keeps distributed-ACME certs in Kubernetes secrets or Vault, never Redis — it backs API Management plan rate-limit and quota counters, which a restart resets to zero and the next request rebuilds."
  type        = bool
  default     = false
}

variable "extra_values" {
  description = "Extra values to merge into the Helm chart values"
  type        = any
  default     = {}
}
