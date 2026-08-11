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
  description = "The git-config-server image (built from terraform/config-server/git/image). The default is a MUTABLE tag, so the Deployment pulls it Always — a rebuild has to actually reach the nodes, and a cached stale layer once served the git repo without the raw /config/ read path at all. Pin :vX.Y.Z (published alongside each library release) or a @sha256 digest for a reproducible apply."
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
  description = "kubectl context for the IngressRoute local-exec apply and the config push port-forward — the ambient context the compute module merges (k3s-<vm_name> / gke-<cluster> / oke-<cluster>). Empty = ambient default context (fine for a single demo; parallel standups MUST pin it)."
  type        = string
  default     = ""
}

variable "files" {
  description = "The config repo's desired content: repo path -> file content (e.g. { \"vm/dynamic.yaml\" = yamlencode(...) }). Non-empty makes terraform PUSH the tree on every content change — one commit replacing the repo's previous tree — and the post-receive hook publishes it raw at https://<ingress_host>/config/<path>, which is what a Hub provider's configEndpoint polls. The push rides a kubectl port-forward straight to the Service, so it needs neither the git.<domain> DNS record nor the ingress cert to be ready — a fresh standup can push before dns-traefiker/ACME converge. This is the GitOps write path: changing routing intent re-runs only this push, never a gateway VM."
  type        = map(string)
  default     = {}
}
