variable "apps" {
  description = "Map of applications to deploy as KubeVirt guests: { name = { replicas, port, name, environment, traefik_labels } }. `traefik_labels` (dotted Traefik label -> value) is rendered as LINE-format `traefik.key=value` labels, one per line, into the VirtualMachine's `label_annotation`. UNLIKE apps/whoami/proxmox, `replicas > 1` TOGETHER WITH traefik_labels is legal and is the recommended shape: the kubevirt provider MERGES same-named services across VMs, so one identical label map on N guests builds one N-server load balancer. Give every guest of an app the SAME labels — a per-guest unique service name would defeat the merge."
  type        = any
  default     = {}
}

variable "namespace" {
  description = "Namespace the VirtualMachines are created in. It must permit privileged pods (PodSecurity `enforce: privileged`): virt-launcher needs /dev/kvm and tun, which baseline and restricted both reject."
  type        = string
  default     = "apps"
}

# --- Workload -----------------------------------------------------------------------
variable "whoami_image" {
  description = "OCI image whose whoami binary (entrypoint /whoami) is EXTRACTED with crane and run raw under the guest's systemd — there is no container runtime in the VM. Default is the OTel-instrumented fork, so the guests honour the OTEL_* env below and earn their own service-graph node. An untagged reference resolves to `:latest`, crane's own default."
  type        = string
  default     = "ghcr.io/traefik-workshops/whoami:latest"
}

variable "crane_version" {
  description = "go-containerregistry release whose static `crane` binary the guest fetches to export whoami_image's rootfs — no docker needed anywhere. Pinned, never `latest`: the guest downloads this at first boot, so a moving reference would change the demo's floor mid-standup. NB apps/whoami/proxmox pins v0.20.2 for the same job; the two are independent and neither needs to follow the other."
  type        = string
  default     = "v0.20.3"
}

variable "environment" {
  description = "Environment variables written into every guest's whoami systemd unit (the OTel block, typically). WHOAMI_NAME is set from each app's `name` first, so an entry here still wins; a per-app `environment` wins over both."
  type        = map(string)
  default     = {}
}

# --- Guest shape --------------------------------------------------------------------
variable "container_disk" {
  description = "containerDisk image backing each guest's root disk — a read-only OCI root with an ephemeral overlay, so no PVC, no StorageClass and no CDI DataVolume. Must be a cloud-init-enabled image with a working package manager: the guest installs curl/tar at first boot. Ubuntu rather than Fedora by default, which also keeps the image consistent with the docker-in-VM legs whose shared cloud-init snippet only installs the Docker ENGINE on apt distros."
  type        = string
  default     = "quay.io/containerdisks/ubuntu:24.04"
}

variable "memory" {
  description = "Guest memory (spec.template.spec.domain.memory.guest), e.g. \"2Gi\"."
  type        = string
  default     = "2Gi"
}

variable "cores" {
  description = "vCPU cores per guest (spec.template.spec.domain.cpu.cores)."
  type        = number
  default     = 2
}

variable "run_strategy" {
  description = "VirtualMachine runStrategy. `Always` keeps the guest running and restarts it if it stops. Never set this AND `running` — the API server rejects a VM that carries both, which is why this module has no `running` input."
  type        = string
  default     = "Always"
}

variable "common_labels" {
  description = "Labels applied to every VirtualMachine AND to its VMI template (virt-controller copies VMI labels onto the launcher pod). Merged UNDER the module's own `app.kubernetes.io/name`."
  type        = map(string)
  default     = {}
}

# --- Discovery ----------------------------------------------------------------------
variable "label_annotation" {
  description = "Annotation on the VirtualMachine carrying the LINE-format `traefik.key=value` block — the provider's --hub.providers.kubevirt.labelAnnotation. The default is Harvester's Description field, so an operator can configure routing by typing into the VM's Description box with no manifest and no kubectl. Set to \"\" to emit each label as its OWN `traefik.*` annotation instead; that form is only safe for SHORT keys, because an annotation KEY is capped at 63 characters and several real Traefik label keys are longer (see the README)."
  type        = string
  default     = "field.cattle.io/description"
}
