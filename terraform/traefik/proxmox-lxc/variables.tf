# --- Placement -------------------------------------------------------------------
variable "node_name" {
  type        = string
  description = "Proxmox VE node the gateway container runs on."
}

variable "datastore_id" {
  type        = string
  description = "Datastore backing the container's root filesystem."
  default     = "local-lvm"
}

variable "bridge" {
  type        = string
  description = "Linux bridge the container joins — the same guest network the whoami containers and the hub sit on, since the hub dials this gateway's uplink across it."
  default     = "vmbr0"
}

variable "container_name" {
  type        = string
  description = "Hostname of the gateway container. Name it for the compute type it fronts (e.g. traefik-lxc) — PVE keys guests on VMID, not name, so a duplicate name is not an error, just an ambiguous `pct list` and dashboard."
  default     = "traefik-lxc"
}

variable "lxc_template_file_id" {
  type        = string
  description = "OS template file ID, e.g. \"local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst\". Must be a systemd Debian template — the Hub rides its init."
  default     = ""
}

variable "num_cpus" {
  type        = number
  description = "vCPUs for the gateway container."
  default     = 2
}

variable "memory" {
  type        = number
  description = "RAM (MB) for the gateway container."
  default     = 1024
}

variable "disk_size" {
  type        = number
  description = "Root filesystem size (GB). The extracted Hub binary is ~17MB plus crane; 4GB is ample."
  default     = 4
}

# --- Addressing (static, non-negotiable) -------------------------------------------
variable "ip_address" {
  type        = string
  description = "STATIC CIDR for the gateway container, e.g. \"10.10.10.50/24\". Required: the hub dials https://<ip>:9443 for the multicluster uplink, so the address must be known at plan time — and a container reports no DHCP lease back to terraform (no guest agent), so DHCP would leave the hub with nothing to dial. Keep it outside any DHCP pool on the bridge."
}

variable "gateway" {
  type        = string
  description = "Default gateway for the static address — normally the internal bridge's own IP."
}

# --- Node access (the pct-exec provisioning channel) --------------------------------
variable "node_ssh" {
  description = "SSH access to the Proxmox NODE, used to `pct push`/`pct exec` the Hub install into the container (LXC has no cloud-init user-data path). The user needs passwordless sudo — pct is root-only."
  type = object({
    host        = string
    user        = optional(string, "root")
    private_key = string
  })
  sensitive = true
}

variable "crane_version" {
  type        = string
  description = "go-containerregistry release whose static `crane` binary extracts the Hub binary out of the OCI image (no docker daemon in the container)."
  default     = "v0.20.2"
}

# --- Licensing --------------------------------------------------------------------
variable "traefik_hub_token" {
  type        = string
  description = "Traefik Hub license token. Delivered via /etc/traefik-hub/env (0600) and injected as --hub.token=$HUB_TOKEN by systemd, so it never appears in the process args."
  sensitive   = true
  default     = ""
}

# --- Feature flags ----------------------------------------------------------------
variable "enable_api_gateway" {
  type        = bool
  description = "Run the API Gateway (Hub) rather than plain Traefik."
  default     = true
}

variable "enable_ai_gateway" {
  type        = bool
  description = "Enable the AI Gateway."
  default     = false
}

variable "enable_mcp_gateway" {
  type        = bool
  description = "Enable the MCP Gateway."
  default     = false
}

variable "enable_offline_mode" {
  type        = bool
  description = "Run the Hub OFFLINE (license carries offline:true; no reporting to hub.traefik.io) — the natural mode for an air-gap-ish lab."
  default     = false
}

variable "enable_debug" {
  type        = bool
  description = "Debug mode."
  default     = false
}

variable "enable_dashboard" {
  type        = bool
  description = "Serve the Traefik dashboard."
  default     = true
}

variable "dashboard_insecure" {
  type        = bool
  description = "Serve the dashboard without auth (lab default)."
  default     = true
}

variable "dashboard_entrypoints" {
  type        = list(string)
  description = "Entrypoints the dashboard router binds."
  default     = ["traefik"]
}

variable "dashboard_match_rule" {
  type        = string
  description = "Router rule for the dashboard."
  default     = ""
}

# --- Versions & images -------------------------------------------------------------
variable "traefik_chart_version" {
  type        = string
  description = "Traefik Helm chart version the shared module templates the static config from."
  default     = "40.3.0"
}

variable "traefik_tag" {
  type        = string
  description = "Traefik OSS image tag."
  default     = ""
}

variable "traefik_hub_tag" {
  type        = string
  description = "Traefik Hub release tag."
  default     = "v3.20.4"
}

variable "traefik_hub_preview_tag" {
  type        = string
  description = "Traefik Hub preview tag."
  default     = ""
}

variable "custom_image_registry" {
  type        = string
  description = "Registry of the image the Hub binary is EXTRACTED from. Must be the same build the rest of the mesh runs — a child on a different Hub version cannot join the uplink."
  default     = ""
}

variable "custom_image_repository" {
  type        = string
  description = "Repository of the image the Hub binary is extracted from."
  default     = ""
}

variable "custom_image_tag" {
  type        = string
  description = "Tag of the image the Hub binary is extracted from."
  default     = ""
}

# --- Observability ----------------------------------------------------------------
variable "log_level" {
  type        = string
  description = "Traefik log level."
  default     = "INFO"
}

variable "otlp_address" {
  type        = string
  description = "OTLP endpoint this gateway ships to (the hub collector's ingress). Must be resolvable AND trusted from inside the container."
  default     = ""
}

variable "otlp_service_name" {
  type        = string
  description = "service.name this gateway reports as — its node in the Tempo service graph. Name it for the compute type it fronts (traefik-lxc), pairing with its backend (whoami-lxc) the way the sibling demos pair traefik-<type> -> whoami-<type>."
  default     = "traefik-lxc"
}

variable "enable_otlp_access_logs" {
  type        = bool
  description = "Ship access logs over OTLP."
  default     = false
}

variable "enable_otlp_application_logs" {
  type        = bool
  description = "Ship application logs over OTLP."
  default     = false
}

variable "enable_otlp_metrics" {
  type        = bool
  description = "Ship metrics over OTLP."
  default     = false
}

variable "enable_otlp_traces" {
  type        = bool
  description = "Ship traces over OTLP."
  default     = false
}

variable "enable_prometheus" {
  type        = bool
  description = "Expose the Prometheus endpoint."
  default     = false
}

variable "enable_access_logs" {
  type        = bool
  description = "Enable access logs."
  default     = true
}

# --- Guest discovery (the NX211 plugin) ---------------------------------------------
variable "proxmox_plugin" {
  description = "NX211 traefik-proxmox-provider config — the same runtime Yaegi plugin the VM child runs, so Traefik downloads it from plugins.traefik.io at start (the container NEEDS outbound internet or Traefik exits). It discovers EVERY guest labelled traefik.enable=true and cannot be scoped by node/type/tag, so this gateway sees the VM guests too; that is expected. What makes this the LXC gateway is that file_provider_config only advertises the LXC services."
  type = object({
    enabled          = optional(bool, true)
    version          = optional(string, "v0.8.1")
    poll_interval    = optional(string, "30s")
    api_endpoint     = string
    api_token_id     = string
    api_validate_ssl = optional(bool, false)
    api_logging      = optional(string, "")
  })
  default = {
    enabled      = false
    api_endpoint = ""
    api_token_id = ""
  }
}

variable "proxmox_api_token" {
  type        = string
  description = "Secret half of the PVE API token the plugin discovers with (Proxmox has no ambient identity, so this is explicit). Use the read-only discovery token — demo-grade in the process args either way."
  sensitive   = true
  default     = ""
}

# --- Config extension --------------------------------------------------------------
variable "custom_plugins" {
  description = "Extra Traefik plugins beyond the proxmox discovery plugin (which has its own proxmox_plugin variable)."
  type        = any
  default     = {}
}

variable "custom_ports" {
  description = "Extra entrypoints. Carries the multicluster uplink, e.g. { lxcuplink = { port = 9443, uplink = true, expose = { default = true }, http = { tls = { enabled = true } } } }. Typed `any` because that shape is nested."
  type        = any
  default     = {}
}

variable "custom_arguments" {
  type        = list(string)
  description = "Extra Traefik CLI arguments."
  default     = []
}

variable "custom_envs" {
  description = "Extra environment variables for the Hub process."
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "file_provider_config" {
  type        = string
  description = "The file provider's dynamic config (YAML). THIS is what makes this the LXC gateway: the plugin discovers every guest indiscriminately, so the compute-type separation is enforced here — advertise ONLY the LXC services (e.g. lxc-whoami@plugin-proxmox) and never the VM ones. Also where uplinks are declared for the hub to surface as <uplink>@multicluster."
  default     = ""
}

variable "file_provider_path" {
  type        = string
  description = "Directory the file provider watches inside the container."
  default     = "/etc/traefik-hub/dynamic"
}

variable "multicluster_provider" {
  description = "Multicluster provider config. { enabled = true } makes this a CHILD the hub can dial."
  type        = any
  default     = { enabled = false }
}
