variable "name" {
  description = "Name for the git-config-server Deployment/Service/IngressRoute."
  type        = string
  default     = "git-config-server"
}

variable "namespace" {
  description = "Namespace to deploy into (the demo's traefik namespace, so it shares the hub's ingress)."
  type        = string
}

variable "image" {
  description = "The git-config-server image (built from terraform/config-server/git/image)."
  type        = string
  default     = "ghcr.io/traefik-workshops/git-config-server:latest"
}

variable "ingress_host" {
  description = "Host the repo is served at — git.<domain>. Spokes clone https://<this>/config.git; terraform pushes to the same."
  type        = string
}

variable "ingress_entrypoint" {
  description = "Traefik entrypoint the IngressRoute binds — the hub's public HTTPS entrypoint (websecure), so spokes reach it exactly like collector.<domain>."
  type        = string
  default     = "websecure"
}

variable "kubeconfig_context" {
  description = "kubectl context for the IngressRoute local-exec apply — the ambient context the k3s module merges (k3s-<vm_name>). Empty = ambient default context."
  type        = string
  default     = ""
}
