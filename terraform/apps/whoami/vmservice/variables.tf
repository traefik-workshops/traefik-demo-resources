variable "apps" {
  description = "Map of applications to deploy as VM Service VMs. Each app can have multiple replicas. { name = { replicas, port, name, environment, traefik_labels } } — `traefik_labels` (map of dotted Traefik labels, e.g. traefik.enable=true + traefik.http.services.<svc>.loadbalancer.server.port=80) is rendered line by line into ONE annotation on each VirtualMachine CR (see label_annotation), which is where the Hub vmoperator provider reads it; identical blocks on N replicas merge into one N-server service on the gateway. Optional `environment` (map) is merged over the module-level `environment` into the container. The app KEY becomes the VirtualMachine name prefix (`<key>-<n>`): make it unique in the vCenter inventory."
  type        = any
  default     = {}
}

# --- vSphere Namespace placement (what VM Service needs) ----------------------------
variable "namespace" {
  type        = string
  description = "vSphere Namespace (a Supervisor namespace) the VirtualMachines are created in. The VirtualMachineClass, the storage class and the image must all be associated with it."
}

variable "class_name" {
  type        = string
  description = "VirtualMachineClass the VMs are sized by (e.g. best-effort-small). `kubectl get virtualmachineclass -n <namespace>` lists the ones bound to the namespace."
}

variable "image_name" {
  type        = string
  description = "VirtualMachineImage the VMs boot from — the name `kubectl get vmi -n <namespace>` shows (a content-library OVF item the namespace can see). Must be a cloud-init-enabled Ubuntu CLOUD IMAGE (ubuntu-*-server-cloudimg-amd64.ova) for the rawCloudConfig bootstrap to take."
}

variable "storage_class" {
  type        = string
  description = "Storage class for the VMs' disks (the namespace's storage policy, e.g. wcp-storage)."
}

variable "network_name" {
  type        = string
  default     = ""
  description = "Network the VMs' single interface joins (an NSX segment or VDS port group the namespace is entitled to). Empty = the namespace's default network, which is what a plain `VirtualMachine` with no `network` block gets."
}

variable "api_version" {
  type        = string
  default     = "v1alpha3"
  description = "vmoperator.vmware.com API version to write the VirtualMachine with (`kubectl api-resources | grep vmoperator` shows what a Supervisor serves). The module adapts the VM spec to it: v1alpha1 (vSphere 8U2's WCP serves ONLY this) uses spec.vmMetadata + the lowercase powerState enum; v1alpha2+ (VCF 9) uses spec.bootstrap.cloudInit. Point the vmoperator PROVIDER at the same version."
}

# --- Workload -----------------------------------------------------------------------
variable "whoami_image" {
  description = "Whoami image to docker-run on each VM. Untagged references get `:` + whoami_version appended."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "whoami_version" {
  description = "Image tag used only when whoami_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0)."
  type        = string
  default     = "v1.11.0"
}

variable "environment" {
  description = "Environment variables passed to every whoami container (docker -e), e.g. OTEL_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision."
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Kubernetes labels applied to every VirtualMachine and its bootstrap Secret, merged UNDER the module's own `app.kubernetes.io/name`."
  type        = map(string)
  default     = {}
}

# --- Discovery: the label block in ONE annotation on the VirtualMachine CR -----------
variable "label_annotation" {
  description = "Annotation on the VirtualMachine carrying the LINE-format `traefik.key=value` block — the provider's --hub.providers.vmoperator.labelAnnotation. Set to \"\" to emit each label as its OWN `traefik.*` annotation instead; that form is only safe for SHORT keys, because an annotation KEY is capped at 63 characters and several real Traefik label keys are longer."
  type        = string
  default     = "traefik.io/config"
}

# --- Supervisor access for the wait script -------------------------------------------
variable "kubeconfig" {
  type        = string
  default     = ""
  description = "Path to the kubeconfig the guest-address wait (local-exec kubectl) should use — the SUPERVISOR kubeconfig, the same one the kubectl provider that creates the VirtualMachine is configured with. Empty = kubectl's ambient config."
}

variable "kubeconfig_context" {
  type        = string
  default     = ""
  description = "Context inside `kubeconfig` to use. Set it so the wait targets a named context instead of whatever the machine-global current-context happens to be at that instant (a parallel standup or a mid-apply context switch would otherwise poll the WRONG cluster)."
}

variable "ip_wait_timeout" {
  type        = number
  default     = 600
  description = "Seconds to wait for each VM's status.network.primaryIP4 before failing the apply. vm-operator powers the VM on and NSX assigns the address within a minute or two on a healthy Supervisor; a first boot that pulls the image into the namespace can take longer."
}
