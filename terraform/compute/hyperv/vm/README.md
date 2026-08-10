# compute/hyperv/vm

The shared **Hyper-V VM primitive**. Standalone Hyper-V has no REST API and no Terraform provider in this stack — management is PowerShell — so each VM is a **host-side PowerShell one-shot over WinRM HTTPS**: the caller-rendered NoCloud seed files are uploaded, `scripts/new-vm.ps1` builds the seed ISO with the IMAPI2FS COM API (volume label `cidata`, **asserted** after the build — a wrong label makes cloud-init silently ignore the seed), creates a **differencing VHDX** off the read-only golden parent, and boots a Gen 2 VM (Secure Boot on the Microsoft UEFI CA template). A change to any seed payload replaces the VM, mirroring the proxmox module's hash-named-snippet mechanism.

`traefik/hyperv-vm` (one gateway VM), `apps/whoami/hyperv` (N whoami VMs) and `compute/hyperv/k3s` (the hub VM) all compose this module. It owns **no role config**: `user_data` and `network_config` arrive as opaque per-instance strings, and there is deliberately **no description/notes input** — on the SCVMM topology the `traefik.*` label carrier is the **VMM-side VM Description** (`Set-SCVirtualMachine`, see `apps/whoami/hyperv`), and the host-side Hyper-V Notes field is never read by discovery.

**Addressing is static by design.** Hyper-V's only guest-IP readback (KVP) is not plan-readable, so the caller plans every address: each instance's `network-config` assigns it and `ip_address` echoes it through the outputs. Plan-known addresses are what make hub→child uplink wiring single-pass on this platform.

## Example usage

```hcl
module "vm" {
  source = "git::https://github.com/traefik-workshops/traefik-demo-resources.git//terraform/compute/hyperv/vm?ref=v6.1.2"

  host_winrm = {
    host     = "203.0.113.10" # the Hyper-V host's WinRM HTTPS listener
    username = "Admin"
    password = var.host_admin_password
  }

  switch_name      = "traefik-lab"
  parent_vhdx_path = "C:\\traefik-lab\\golden\\noble-golden.vhdx"

  instances = {
    "whoami-vm-1" = {
      user_data      = local.rendered_cloud_init
      network_config = local.rendered_network_config # assigns 10.99.0.31/24
      ip_address     = "10.99.0.31"
    }
  }
}
```

## Prerequisites

- A WinRM **HTTPS** listener on the Hyper-V host (`:5986`, self-signed is fine with the default `insecure = true`), reachable from wherever terraform runs, with a Hyper-V-administrator account (NTLM).
- The golden parent VHDX: a generic Ubuntu **cloud image** converted qcow2→VHDX (**never** the `-azure.vhd` artifact — it pins `datasource_list: [Azure]` and ignores NoCloud) with `linux-cloud-tools` (the KVP daemon) baked in, marked read-only. The hyperv demo's host prep builds exactly this.
- Teardown talks to the host: destroy the guests while the host is reachable, or fall back to destroying the host itself.
- PowerShell quoting rule for anything derived from this module's scripts: single-quoted strings do **not** collapse backtick escapes (`'HostSNI(``*``)'` stores two literal backticks) — use double quotes or base64 for values that can carry backticks.
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

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.vm](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_host_winrm"></a> [host\_winrm](#input\_host\_winrm) | WinRM HTTPS access to the Hyper-V HOST the VMs are created on (the host has no API; every operation is a PowerShell one-shot over this listener). NTLM with a local or domain account that is a Hyper-V administrator. insecure defaults true — self-signed listeners are the lab norm. | <pre>object({<br/>    host     = string<br/>    port     = optional(number, 5986)<br/>    username = string<br/>    password = string<br/>    https    = optional(bool, true)<br/>    insecure = optional(bool, true)<br/>    use_ntlm = optional(bool, true)<br/>    timeout  = optional(string, "10m")<br/>  })</pre> | n/a | yes |
| <a name="input_parent_vhdx_path"></a> [parent\_vhdx\_path](#input\_parent\_vhdx\_path) | Host path of the READ-ONLY golden parent VHDX every VM's differencing disk chains to. Must be a generic Ubuntu CLOUD IMAGE converted qcow2->VHDX (NEVER the -azure.vhd artifact — it pins datasource\_list to [Azure] and ignores NoCloud seeds) with linux-cloud-tools (the KVP daemon) baked in. | `string` | n/a | yes |
| <a name="input_generation"></a> [generation](#input\_generation) | Hyper-V VM generation. 2 (the default) boots the Ubuntu cloud image via UEFI with Secure Boot on the Microsoft UEFI CA template; only change it for exotic guests. | `number` | `2` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of VMs to create, keyed by VM name (also the guest hostname via the rendered meta-data). user\_data / network\_config are the already-rendered NoCloud payloads (opaque). ip\_address is the PLAN-KNOWN guest address the network\_config assigns (bare IP, no CIDR) — the module cannot parse it out of the opaque payload, so the caller states it once more and the outputs echo it; nothing here discovers addresses (see main.tf header). | <pre>map(object({<br/>    user_data      = string<br/>    network_config = string<br/>    ip_address     = string<br/>    memory         = optional(number)<br/>    num_cpus       = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB per VM (STATIC — dynamic memory is disabled so k3s/whoami sizing behaves; per-instance override via instances.*.memory) | `number` | `4096` | no |
| <a name="input_num_cpus"></a> [num\_cpus](#input\_num\_cpus) | vCPU count per VM (per-instance override via instances.*.num\_cpus) | `number` | `2` | no |
| <a name="input_switch_name"></a> [switch\_name](#input\_switch\_name) | Name of the Hyper-V virtual switch each VM's NIC joins (the demo host preps an internal NAT switch; addressing is STATIC via each instance's network-config — there is no DHCP assumption). | `string` | `"traefik-lab"` | no |
| <a name="input_workdir"></a> [workdir](#input\_workdir) | Host directory the module works under: seed files + ISOs in <workdir>\seeds\<name>, differencing disks in <workdir>\vms\<name>. | `string` | `"C:\\traefik-lab"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instances"></a> [instances](#output\_instances) | Map of the created VMs with their details (keyed by VM name). private\_ip and public\_ip are the SAME statically-planned guest address — Hyper-V guests have one primary IP and no cloud public-IP concept (kept for sibling-parity). |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Map of instance names to their statically-planned guest IP addresses (known at PLAN time — the property that makes hub->child uplink addresses single-pass on Hyper-V) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Map of instance names to their guest IP addresses — identical to private\_ips (no public-IP concept on Hyper-V; kept for sibling-parity) |
<!-- END_TF_DOCS -->
