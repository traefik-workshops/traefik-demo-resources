variable "name" {
  type        = string
  description = "Name for the user pool and app client, and (via domain_prefix's default, underscores → hyphens) the hosted domain. Cognito domains are GLOBALLY unique per region, so give every stack deployed into the same AWS account/region its own name — two deployments sharing the default collide on the domain."
  default     = "traefik-demo"
}

variable "domain_prefix" {
  type        = string
  description = "Explicit Cognito hosted-domain prefix. Empty (the default) derives it from name (underscores → hyphens). Needed when name contains a substring AWS forbids in domain prefixes (\"aws\", \"amazon\", \"cognito\")."
  default     = ""
}

variable "enable_unique_domain" {
  type        = bool
  description = "Append a random suffix to the hosted-domain prefix so same-named stacks can't collide on the region-global domain namespace. Default off — the domain is exactly the name-derived prefix; flipping this on an EXISTING deployment replaces the domain."
  default     = false
}

variable "users" {
  type        = list(string)
  default     = ["admin", "support"]
  description = "List of Cognito users to be created"
}

variable "redirect_uris" {
  type        = list(string)
  default     = []
  description = "Allowed callback URL for the authentication flow"
}

variable "user_password" {
  description = "Initial password assigned to every created Cognito user. Demo default — override for anything beyond ephemeral PoCs."
  type        = string
  sensitive   = true
  default     = "topsecretpassword"
}
