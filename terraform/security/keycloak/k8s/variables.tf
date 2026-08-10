variable "name" {
  description = "The name of the traefik release"
  type        = string
  default     = "traefik"
}

variable "namespace" {
  description = "Namespace for the Traefik Hub deployment"
  type        = string
}

variable "domain" {
  type        = string
  default     = ""
  description = "Base domain for ingress (e.g., benchmarks.demo.traefik.ai)"
}

variable "ingress" {
  type = object({
    enabled    = optional(bool, false)
    internal   = optional(bool, true)
    domain     = optional(string, "")
    entrypoint = optional(string, "traefik")
  })
  default     = {}
  description = "Ingress configuration for the keycloak service"
}

variable "ingress_observability" {
  type        = bool
  description = "Emit Traefik observability signals (access logs, metrics, traces) for the Keycloak ingress router. Set to false to add the three `traefik.ingress.kubernetes.io/router.observability.*: \"false\"` annotations. Same switch shape as other k8s modules."
  default     = true
}

variable "ingress_annotations" {
  type        = map(string)
  description = "Additional metadata annotations merged onto the Ingress. Useful for custom router options beyond the three observability toggles."
  default     = {}
}

variable "users" {
  description = "List of users to create in the security module"
  type        = list(string)
}

variable "user_password" {
  description = "Initial password assigned to every simple user (the `users` list). Demo default — override for anything beyond ephemeral PoCs. `advanced_users` carry their own password. The same value seeds the realm credential and is replayed by the token-fetch Job, so the two can never drift."
  type        = string
  sensitive   = true
  default     = "topsecretpassword"
}

variable "redirect_uris" {
  type        = list(string)
  default     = []
  description = "Allowed callback URL for the authentication flow"
}

variable "advanced_users" {
  description = "List of advanced users with detailed configuration including groups and claims"
  type = list(object({
    username = string
    email    = string
    password = string
    groups   = list(string)
    claims   = map(list(string))
  }))
  default = []
}

variable "access_token_lifespan" {
  description = "The lifespan of the access token in seconds"
  type        = number
  default     = 2419200 # 28 days
}

variable "standard_token_exchange" {
  description = "Allow the `traefik` client to perform RFC 8693 standard token exchange (Keycloak 26.2+). Sets the client's `standard.token.exchange.enabled` attribute; the server-side feature is already enabled by default. Required by any middleware that exchanges a subject token at this realm's token endpoint."
  type        = bool
  default     = false
}

variable "host" {
  description = "Kubernetes API server URL for the cluster Keycloak runs on. Used by the token-capture data source to build an isolated kubectl context when reading from a remote cluster. Leave empty to use the ambient kubeconfig."
  type        = string
  default     = ""
}

variable "client_certificate" {
  description = "PEM-encoded client certificate matching `host`. Written to a temp file for the token-capture kubectl context. Required when `host` is set."
  type        = string
  default     = ""
}

variable "client_key" {
  description = "PEM-encoded client key matching `client_certificate`. Written to a temp file for the token-capture kubectl context. Required when `host` is set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "kubeconfig" {
  description = "Path to a kubeconfig file for the token-capture data source. Takes precedence over `host` and the ambient kubeconfig. Use when the ambient context may not point at the cluster Keycloak runs on (e.g. exec-auth clusters like EKS, where `host`/`client_certificate` don't apply)."
  type        = string
  default     = ""
}

variable "kubeconfig_context" {
  description = "kubectl context for the token-capture data source. Set it so the read targets a named context instead of the machine-global current-context (a data source re-evaluates at plan/refresh/destroy, so a parallel standup or a mid-run context switch would otherwise read the WRONG cluster). Combines with `kubeconfig` (context within that file); ignored when `host`/`client_certificate` build their own isolated context. Empty = ambient current-context — today's behavior."
  type        = string
  default     = ""
}

variable "instances" {
  type        = number
  default     = 1
  description = "Number of Keycloak pods behind the shared Postgres backend. Scale when multiple independent test runs hit the OIDC endpoint in parallel."
}

variable "chart" {
  type        = string
  default     = ""
  description = "Helm chart for the Keycloak deployment: a local path, or a fully-qualified OCI reference (oci://ghcr.io/traefik-workshops/keycloak). OCI consumers should pin chart_version."
}

variable "chart_version" {
  type        = string
  default     = ""
  description = "Chart version to install. Required in practice for OCI charts (unpinned resolves the latest tag — not reproducible); ignored for local chart paths, which carry no version."
}
