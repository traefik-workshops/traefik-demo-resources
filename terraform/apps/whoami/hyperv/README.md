# apps/whoami/hyperv

whoami on **Hyper-V VMs under SCVMM** — the on-prem sibling of `apps/whoami/proxmox` / `apps/whoami/vsphere`, discovered by the native first-party Hub **Hyper-V provider** (`--hub.providers.hyperv.*`, SCVMM-based; see `traefik/hyperv-vm`).

**The label carrier is the SCVMM VM Description, the grammar is proxmox's**: line-format `traefik.<key>=<value>`, one per line (`traefik.enable=true` mandatory; blank lines and `# comments` tolerated). The provider reads it from the **VMM server** (`Get-SCVirtualMachine`) — the host-side Hyper-V Notes field is never read.

**Two planes, two connections** — the module split the SCVMM topology demands:

| plane | connection | does |
|---|---|---|
| VM creation | `host_winrm` → the Hyper-V **host** | differencing VHDX + NoCloud seed one-shots (`compute/hyperv/vm`) |
| label writing | `vmm` → the **SCVMM server** | `Set-SCVirtualMachine -Description` (VMM-write account) |

A label change re-runs **only the writer** — never a VM replacement. Labels ride **base64** end to end because of the PowerShell quoting trap: single-quoted strings do *not* collapse backtick escapes (`'HostSNI(``*``)'` stores two literal backticks), so interpolating label values that carry `` Host(`...`) `` backticks corrupts them — use double quotes where interpolation is unavoidable; this module avoids it entirely.

**The provider merges same-named services across VMs** (vsphere/EC2-style, *not* proxmox's one-service-per-guest): identical labels on N replicas fold into one N-server load balancer, and per-service `loadbalancer.strategy` labels (`leasttime`, `hrw`) apply to the whole merged pool — no terraform-wired server lists, no weighted file compositions.

## Example usage

```hcl
module "hyperv_whoami" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/apps/whoami/hyperv?ref=v8.0.0"

  host_winrm       = { host = "203.0.113.10", username = "Admin", password = var.host_admin_password }
  vmm              = { host = "10.99.0.6", username = "LAB\\Administrator", password = var.lab_admin_password }
  parent_vhdx_path = "C:\\traefik-lab\\golden\\noble-golden.vhdx"
  gateway          = "10.99.0.1"
  dns_servers      = ["10.99.0.2"]

  apps = {
    "whoami-vm" = {
      replicas     = 2
      ip_addresses = ["10.99.0.31/24", "10.99.0.32/24"]
      name         = "whoami-vm"
      traefik_labels = {
        "traefik.enable"                                                 = "true"
        "traefik.http.services.vm-rr.loadbalancer.server.port"           = "80"
        "traefik.http.services.vm-leasttime.loadbalancer.server.port"    = "80"
        "traefik.http.services.vm-leasttime.loadbalancer.strategy"       = "leasttime"
      }
    }
  }
}
```

## Prerequisites

- Everything `compute/hyperv/vm` needs (host WinRM HTTPS, golden parent VHDX, the virtual switch).
- An SCVMM management server whose WinRM HTTPS listener the label writer can reach, and a **VMM-write** account (the gateway's read-only discovery account cannot `Set-SCVirtualMachine`).
- The Hyper-V host under VMM management with a healthy agent — the writer force-refreshes hosts while waiting for a just-created VM to appear in the VMM inventory.
- See the [repo-wide AGENTS.md](../../../../AGENTS.md) for conventions.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloud_init"></a> [cloud\_init](#module\_cloud\_init) | ../cloud-init | n/a |
| <a name="module_vm"></a> [vm](#module\_vm) | ../../../compute/hyperv/vm | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.labels](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_gateway"></a> [gateway](#input\_gateway) | Default gateway for the VMs — the Hyper-V internal NAT switch's host-side address (e.g. 10.99.0.1). | `string` | n/a | yes |
| <a name="input_host_winrm"></a> [host\_winrm](#input\_host\_winrm) | WinRM HTTPS access to the Hyper-V HOST the VMs are created on (see compute/hyperv/vm). This is the CREATION plane — labels never travel over it. | <pre>object({<br/>    host     = string<br/>    port     = optional(number, 5986)<br/>    username = string<br/>    password = string<br/>    https    = optional(bool, true)<br/>    insecure = optional(bool, true)<br/>    use_ntlm = optional(bool, true)<br/>    timeout  = optional(string, "10m")<br/>  })</pre> | n/a | yes |
| <a name="input_parent_vhdx_path"></a> [parent\_vhdx\_path](#input\_parent\_vhdx\_path) | Golden parent VHDX every VM's differencing disk chains to (see compute/hyperv/vm — cloud image, never -azure.vhd, linux-cloud-tools baked in). | `string` | n/a | yes |
| <a name="input_vmm"></a> [vmm](#input\_vmm) | WinRM HTTPS access to the SCVMM MANAGEMENT SERVER, where `Set-SCVirtualMachine -Description` writes each VM's label block. Needs a VMM-WRITE-capable account (an Administrator or a delegated role with VM write on these VMs) — deliberately NOT the gateway's read-only discovery credential. Label changes re-run only this writer, never a VM replacement. | <pre>object({<br/>    host     = string<br/>    port     = optional(number, 5986)<br/>    username = string<br/>    password = string<br/>    timeout  = optional(string, "10m")<br/>  })</pre> | n/a | yes |
| <a name="input_apps"></a> [apps](#input\_apps) | Map of applications to deploy as Hyper-V VMs. Each value: { replicas, ip\_addresses (list of static CIDRs, ONE PER REPLICA — Hyper-V has no plan-readable discovery, so the caller plans the fleet's addresses), port, name, environment, traefik\_labels }. `traefik_labels` (dotted Traefik label -> value) is rendered as LINE-format `traefik.key=value` labels into the SCVMM VM **Description** (VMM-side; the host Notes field is never read). The native provider MERGES same-named services across VMs — identical labels on N replicas fold into one N-server load balancer (vsphere/EC2-style, NOT proxmox's one-service-per-guest) — so a fleet SHARES one label block, and per-service `loadbalancer.strategy` labels (leasttime/hrw) apply to the whole merged pool. | <pre>map(object({<br/>    replicas       = number<br/>    ip_addresses   = list(string)<br/>    port           = optional(number, 80)<br/>    name           = optional(string, "")<br/>    environment    = optional(map(string), {})<br/>    traefik_labels = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | DNS servers for the VMs (the lab router's dnsmasq on the hyperv demo). Static guests get no DHCP: forgetting this leaves whoami unable to resolve its registry or OTLP collector. | `list(string)` | `[]` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables passed to every whoami (docker -e), e.g. OTEL\_* exporter config for the OTel-instrumented whoami fork. Per-app `environment` entries win on collision. | `map(string)` | `{}` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per whoami VM (static memory) | `number` | `1024` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per whoami VM | `number` | `1` | no |
| <a name="input_switch_name"></a> [switch\_name](#input\_switch\_name) | Hyper-V virtual switch the VMs' NICs join. | `string` | `"traefik-lab"` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image docker-run on each VM. Untagged references get `:` + whoami\_version appended. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used only when whoami\_image carries no tag. Must be a real tag for that repository (traefik/whoami tags carry a `v` prefix, e.g. v1.11.0). | `string` | `"v1.11.0"` | no |
| <a name="input_workdir"></a> [workdir](#input\_workdir) | Host directory the VMs' seeds + differencing disks live under. | `string` | `"C:\\traefik-lab"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of all whoami VMs with their details. private\_ip is the statically-PLANNED guest address (an input echoed back — Hyper-V has no plan-readable discovery; the provider reads live addresses from VMM's adapter view at poll time). No public-IP concept on-prem. |
<!-- END_TF_DOCS -->
