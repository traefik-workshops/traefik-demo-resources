# apps/whoami/kubevirt

Runs Traefik `whoami` on **KubeVirt guests** — the VMs behind SUSE Harvester, OpenShift Virtualization and upstream KubeVirt, which are all the same `kubevirt.io/v1` CRDs. Each app replica is one `VirtualMachine`, discovered by the native first-party Hub **kubevirt** provider (`--hub.providers.kubevirt.*`) reading the VM's own annotations.

## The guest runs a native process, not a container

cloud-init crane-extracts the whoami fork's binary (entrypoint `/whoami`) out of its OCI image and runs it **raw under the guest's systemd**. There is no podman, no dockerd, no container runtime of any kind inside the VM.

That is the same trick `apps/whoami/proxmox` uses for its LXC leg, and it is simpler here because a KubeVirt guest *has* a cloud-init user-data path — no `pct push` contortion. Two properties follow, and both are the reason this module exists:

- The process lives in the guest's own UTS namespace, so `os.Hostname()` — the `Hostname:` line in the response body — really is `spec.template.spec.hostname`, not a container id that happens to look like one.
- The leg is a genuinely different **runtime** from an OCI/docker leg on the same substrate, so a demo can put the two side by side without overclaiming.

The binary comes from the instrumented fork rather than an upstream release because the fork honours `OTEL_*`, so these guests emit OTLP and earn their own service-graph node.

## Replicas and service names — the inverse of `apps/whoami/proxmox`

`apps/whoami/proxmox` **forbids** `replicas > 1` together with `traefik_labels`: the proxmox provider's same-named services overwrite each other, so the extra guests would boot, cost resources and never be routed to.

The kubevirt provider **merges** them. `ServersLoadBalancer.Merge` dedupes by server URL and appends, and `mergeable` `DeepEqual`s the rest of the struct — so one **byte-identical** label map on N guests folds into one service with N servers. Here `replicas > 1` with labels is not just legal, it is the shape to use:

```hcl
module "whoami" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/kubevirt?ref=v6.1.3&depth=1"

  namespace      = "apps"
  container_disk = "quay.io/containerdisks/ubuntu:24.04"

  environment = {
    OTEL_TRACES_EXPORTER        = "otlp"
    OTEL_METRICS_EXPORTER       = "otlp"
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    # The guests sit on the POD network under masquerade, so they inherit the launcher
    # pod's cluster DNS and can reach an in-cluster collector Service directly — no lab
    # DNS, no public ingress, no publicly trusted certificate.
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://opentelemetry-collector.observability.svc.cluster.local:4318"
  }

  apps = {
    "whoami-vm" = {
      replicas = 2
      port     = 80
      name     = "whoami-vm" # -> WHOAMI_NAME -> the body's `Name:` line

      # ONE map, IDENTICAL on every guest. Four services per VM, each ending up with
      # `replicas` servers. And because the provider builds no router when a VM declares
      # more than one service, there are zero stray auto-routers to explain away.
      traefik_labels = {
        "traefik.enable"                                              = "true"
        "traefik.http.services.vmrr.loadbalancer.server.port"         = "80"
        "traefik.http.services.vmleasttime.loadbalancer.server.port"  = "80"
        "traefik.http.services.vmleasttime.loadbalancer.strategy"     = "leasttime"
        "traefik.http.services.vmhrw.loadbalancer.server.port"        = "80"
        "traefik.http.services.vmhrw.loadbalancer.strategy"           = "hrw"
      }
    }
  }
}
```

Giving each guest a *unique* service name would defeat the merge and hand you N single-server services instead.

## Why the config rides one annotation

Discovery config travels in **annotations, never labels**: a label value is capped at 63 characters from a restricted alphabet and cannot hold a rule like ``Host(`whoami-vm.example.com`)``.

The provider accepts both the discrete `traefik.<key>` annotation form and a **line-format block in a single annotation** (`label_annotation`, default `field.cattle.io/description`). The default is the block form for two reasons.

An annotation **key** is itself capped at 63 characters, and real Traefik label keys run past it:

| Length | Key | |
| --- | --- | --- |
| 58 | `traefik.http.services.vmleasttime.loadbalancer.server.port` | OK |
| 63 | `traefik.http.services.vmleasttime.loadbalancer.healthcheck.path` | OK, by zero |
| 65 | `traefik.http.services.vmleasttime.loadbalancer.sticky.cookie.name` | **rejected** |
| 67 | `traefik.http.services.vmleasttime.loadbalancer.healthcheck.interval` | **rejected** |

The block lives in one annotation whose **value** has no such limit. Set `label_annotation = ""` only if you know every key is short.

And `field.cattle.io/description` is what Harvester's UI writes when an operator types into a VM's **Description** box — so on Harvester the routing config is editable with no manifest and no `kubectl`.

The annotations go on the **VirtualMachine**, not on `spec.template.metadata`. KubeVirt does not propagate a VM's top-level annotations onto its VMI, and the provider reads the VM object. The payoff is that editing the block is picked up by the provider's refresh poll **without restarting the guest**.

## Four field placements that are easy to get wrong

1. **`hostname` belongs on `spec.template.spec`** (the VMI spec), not on `spec` (the VM spec). A `spec.hostname` is pruned server-side with no error — which leaves `kubectl_manifest` with a permanent non-converging diff and silently voids the distinct-`Hostname:` property.
2. **`cloudInitNoCloud` needs a `disks` entry *and* a `volumes` entry.** Declaring only the volume produces a VM that boots with no user-data and no error; whoami simply never appears.
3. **The identity label is `app.kubernetes.io/name`, never `vm.kubevirt.io/name`.** The latter is KubeVirt's `DeprecatedVirtualMachineNameLabel` and its value is `SanitizeHostname(vmi)`, so it tracks the hostname rather than the VM name. virt-controller copies VMI labels onto the launcher pod, so `app.kubernetes.io/name` is what a Service selects on and what a `kubectl wait -l …` gate should use.
4. **`readinessProbe` is a `tcpSocket`, dialled by the kubelet against the launcher pod.** masquerade forwards it into the guest, so no guest agent is involved — which is what makes `kubectl wait --for=condition=Ready vmi` mean "whoami is listening" rather than "the VMI booted". First boot is minutes (containerDisk pull, apt, crane download, crane export), so without it a caller races an empty pool.

## Networking

`masquerade` with **no `ports` section**: KubeVirt forwards *all* ports into the guest when the section is absent, and SNATs egress through the launcher pod. Two consequences worth knowing:

- The guest inherits the launcher pod's cluster DNS, so it resolves in-cluster Services. That is why the OTLP endpoint in the example above is a `svc.cluster.local` name and not a public ingress host.
- Under masquerade the address in the VMI's `status.interfaces[0]` is the **virt-launcher pod's** IP, populated at network setup with no guest agent involved. So `--hub.providers.kubevirt.ipMode=pod` and `ipMode=interface` resolve to the same address on a single-NIC guest; `pod` reads it off the Pod object, which is stable for the VMI's life, while `interface` reads a status field that can transiently blank out.

## Limitations

- **No storage.** `containerDisk` is a read-only OCI root with an ephemeral overlay: no PVC, no StorageClass, no CDI DataVolume. Nothing in the guest survives a restart, which is correct for whoami and wrong for anything stateful.
- **No `private_ip` output.** The address belongs to the launcher pod (or the VMI status) and is not known to terraform at apply time. The provider resolves it itself on every refresh — which is the point of discovering a VM *as a VM*.
- **No SSH access to the guests.** The user-data installs whoami and nothing else. If a guest never becomes Ready, debug it from inside the cluster (`curl` the launcher pod's IP, `kubectl -n <ns> describe vmi <name>`) or attach a serial console with `virtctl`; there is no key to shell in with.
- **First boot pulls from the internet** (the crane release from GitHub, the whoami image from its registry). Both fetches retry and both fail loud, but an air-gapped cluster needs a pre-baked containerDisk instead.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.14 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 1.14 |

## Resources

| Name | Type |
| ---- | ---- |
| [kubectl_manifest.cloudinit](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.vm](https://registry.terraform.io/providers/gavinbunney/kubectl/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy as KubeVirt guests: { name = { replicas, port, name, environment, traefik\_labels } }. `traefik_labels` (dotted Traefik label -> value) is rendered as LINE-format `traefik.key=value` labels, one per line, into the VirtualMachine's `label_annotation`. UNLIKE apps/whoami/proxmox, `replicas > 1` TOGETHER WITH traefik\_labels is legal and is the recommended shape: the kubevirt provider MERGES same-named services across VMs, so one identical label map on N guests builds one N-server load balancer. Give every guest of an app the SAME labels — a per-guest unique service name would defeat the merge. | `any` | `{}` | no |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Labels applied to every VirtualMachine AND to its VMI template (virt-controller copies VMI labels onto the launcher pod). Merged UNDER the module's own `app.kubernetes.io/name`. | `map(string)` | `{}` | no |
| <a name="input_container_disk"></a> [container\_disk](#input\_container\_disk) | containerDisk image backing each guest's root disk — a read-only OCI root with an ephemeral overlay, so no PVC, no StorageClass and no CDI DataVolume. Must be a cloud-init-enabled image with a working package manager: the guest installs curl/tar at first boot. Ubuntu rather than Fedora by default, which also keeps the image consistent with the docker-in-VM legs whose shared cloud-init snippet only installs the Docker ENGINE on apt distros. | `string` | `"quay.io/containerdisks/ubuntu:24.04"` | no |
| <a name="input_cores"></a> [cores](#input\_cores) | vCPU cores per guest (spec.template.spec.domain.cpu.cores). | `number` | `2` | no |
| <a name="input_crane_version"></a> [crane\_version](#input\_crane\_version) | go-containerregistry release whose static `crane` binary the guest fetches to export whoami\_image's rootfs — no docker needed anywhere. Pinned, never `latest`: the guest downloads this at first boot, so a moving reference would change the demo's floor mid-standup. NB apps/whoami/proxmox pins v0.20.2 for the same job; the two are independent and neither needs to follow the other. | `string` | `"v0.20.3"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables written into every guest's whoami systemd unit (the OTel block, typically). WHOAMI\_NAME is set from each app's `name` first, so an entry here still wins; a per-app `environment` wins over both. | `map(string)` | `{}` | no |
| <a name="input_label_annotation"></a> [label\_annotation](#input\_label\_annotation) | Annotation on the VirtualMachine carrying the LINE-format `traefik.key=value` block — the provider's --hub.providers.kubevirt.labelAnnotation. The default is Harvester's Description field, so an operator can configure routing by typing into the VM's Description box with no manifest and no kubectl. Set to "" to emit each label as its OWN `traefik.*` annotation instead; that form is only safe for SHORT keys, because an annotation KEY is capped at 63 characters and several real Traefik label keys are longer (see the README). | `string` | `"field.cattle.io/description"` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Guest memory (spec.template.spec.domain.memory.guest), e.g. "2Gi". | `string` | `"2Gi"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the VirtualMachines are created in. It must permit privileged pods (PodSecurity `enforce: privileged`): virt-launcher needs /dev/kvm and tun, which baseline and restricted both reject. | `string` | `"apps"` | no |
| <a name="input_run_strategy"></a> [run\_strategy](#input\_run\_strategy) | VirtualMachine runStrategy. `Always` keeps the guest running and restarts it if it stops. Never set this AND `running` — the API server rejects a VM that carries both, which is why this module has no `running` input. | `string` | `"Always"` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | OCI image whose whoami binary (entrypoint /whoami) is EXTRACTED with crane and run raw under the guest's systemd — there is no container runtime in the VM. Default is the OTel-instrumented fork, so the guests honour the OTEL\_* env below and earn their own service-graph node. An untagged reference resolves to `:latest`, crane's own default. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of whoami guests. No private\_ip, unlike the cloud siblings: the address a caller would want belongs to the guest's virt-launcher pod (or its VMI status) and is not known to terraform at apply time — the kubevirt provider resolves it itself, every refresh, which is the whole point of discovering a VM as a VM. `hostname` is what the response body echoes as `Hostname:`. |
| <a name="output_service_names"></a> [service\_names](#output\_service\_names) | Traefik service names the guests' labels declare (the `traefik.http.services.<name>` segment), so a caller can point a file router at a service it knows exists. Because every replica of an app carries the SAME labels and the provider merges same-named services, each of these is ONE service with `replicas` servers behind it. |
| <a name="output_vm_names"></a> [vm\_names](#output\_vm\_names) | VirtualMachine object names, one per replica — the same strings as the guests' hostnames. Useful as a `kubectl wait`/readiness-gate trigger. |
<!-- END_TF_DOCS -->
