variable "name" {
  type        = string
  description = "The name of the loki release"
  default     = "loki"
}

variable "namespace" {
  type        = string
  description = "Namespace for the Grafana deployment"
}

variable "extra_values" {
  type        = any
  description = "Extra values to pass to the Grafana deployment."
  default     = {}
}

variable "persistence" {
  type        = bool
  description = "Back the single-binary Loki and its bundled MinIO with PersistentVolumeClaims instead of emptyDir. Default FALSE — see the teardown note in main.tf: a PVC here becomes a real cloud disk that survives `terraform destroy`. Set true only for an install meant to outlive its pods, and only where something reclaims the disks."
  default     = false
}

variable "tolerations" {
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  description = "Tolerations for the Grafana deployment."
  default     = []
}
