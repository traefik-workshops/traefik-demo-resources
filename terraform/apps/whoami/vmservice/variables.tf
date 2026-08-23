variable "apps" {
  description = "Map of applications to deploy as VM Service VMs. Each app can have multiple replicas. { name = { replicas, port, name, environment, traefik_labels } } — `traefik_labels` (map of dotted Traefik labels, e.g. traefik.enable=true + traefik.http.services.<svc>.loadbalancer.server.port=80) is rendered line by line into each VM's Notes through govc, which is where the Hub vsphere provider reads it; identical blocks on N replicas merge into one N-server service on the gateway. Optional `environment` (map) is merged over the module-level `environment` into the container. The app KEY becomes the VirtualMachine name prefix (`<key>-<n>`): make it unique in the vCenter inventory."
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
  description = "vmoperator.vmware.com API version to write the VirtualMachine with. A Supervisor serves several (`kubectl api-resources | grep vmoperator`); v1alpha3 carries the rawCloudConfig bootstrap this module uses and is served by vSphere 8U2+ and 9."
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

# --- Discovery: the label block in the VM Notes, written through govc ---------------
variable "vsphere_server" {
  type        = string
  description = "vCenter hostname (no scheme) govc writes the VM Notes against. The VM Service VMs live in this vCenter's inventory like any other VM."
}

variable "vsphere_username" {
  type        = string
  description = "vCenter user govc writes the Notes as. Needs the `Virtual machine > Configuration > Set annotation` privilege on the namespace's VMs — a VM-edit right, not a tagging or inventory one."
}

variable "vsphere_password" {
  type        = string
  sensitive   = true
  description = "Password for vsphere_username. Passed to govc through its environment for the duration of the write; never written to disk."
}

variable "allow_unverified_ssl" {
  type        = bool
  default     = true
  description = "Skip vCenter TLS verification in govc (GOVC_INSECURE) — self-signed vCenter certs are the lab norm."
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
