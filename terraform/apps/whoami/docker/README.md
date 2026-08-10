# apps/whoami/docker

Runs Traefik `whoami` as plain **Docker containers**, discovered by a co-located Traefik child through core Traefik's `--providers.docker` reading the local socket. This is the container leg for the demos whose platform has no managed container service to borrow: AWS has ECS, Azure has ACI, OCI and Alibaba have Container Instances, Proxmox has LXC — vSphere, GCE and Morpheus have nothing of the kind.

## This module owns no resources

Like `apps/whoami/cloud-init`, it renders a cloud-init **runcmd fragment** and returns it as the `runcmd` output. The caller feeds that into its Traefik child's `extra_runcmd`, so the containers and the gateway that discovers them are provisioned onto the same VM in one cloud-init pass.

That is forced by the topology, not a convenience. `--providers.docker` talks to `/var/run/docker.sock`; a socket is not a network endpoint, so the containers **must** share a machine with the gateway. Terraform could only own them via the `kreuzwerker/docker` provider, whose `host` would be the gateway VM's address — unknown at plan time on a first apply, and an unknown provider argument is a hard plan error that the demos' two-pass `make up` cannot rescue.

Consequences worth knowing:

- No `instances` map output. There is no terraform-visible id or private IP, so this module breaks the sibling `{ id, name, private_ip }` convention on purpose.
- **Replica changes do not converge.** Cloud-init runs once per instance-id, so raising `replicas` on an existing VM does nothing — the caller has to `-replace` the VM.

## Discovery is labels

`traefik_labels` on each app is the discovery config, the docker provider's equivalent of EC2's dotted tags or GCE's `traefik` metadata item. Every replica of an app carries the **same** `traefik.http.services.<name>` label, which is what makes them servers of one service rather than N single-server services.

Containers are started with no published ports: the gateway container runs `--network host` and already owns `:80`, `:443`, `:8080` and `:9443`. The docker provider hands Traefik each container's own `172.17.0.0/16` bridge address, which the host dials directly.

## Security note

The leg only works if the gateway has the Docker socket bound in (`mount_docker_socket = true` on the Traefik module). That is root-equivalent access to the host — fine for a demo VM whose only workload is whoami, and never appropriate for a gateway fronting anything real.

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps"></a> [apps](#input\_apps) | Apps to run as Docker containers, keyed by app name. Each value: { replicas, name, environment, traefik\_labels }. `name` is the container basename AND the WHOAMI\_NAME the body echoes; `traefik_labels` is the discovery config the local docker provider reads. | `any` | `{}` | no |
| <a name="input_common_labels"></a> [common\_labels](#input\_common\_labels) | Traefik labels applied to every container, merged under each app's own traefik\_labels. | `map(string)` | `{}` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment variables applied to every container (the OTel block, typically). A per-app `environment` wins on collision. | `map(string)` | `{}` | no |
| <a name="input_whoami_image"></a> [whoami\_image](#input\_whoami\_image) | Whoami image to docker-run. A tag in the last path segment wins over whoami\_version. | `string` | `"ghcr.io/traefik-workshops/whoami:latest"` | no |
| <a name="input_whoami_version"></a> [whoami\_version](#input\_whoami\_version) | Image tag used ONLY when whoami\_image carries none. | `string` | `"v1.11.0"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_names"></a> [container\_names](#output\_container\_names) | Container names as they will appear in `docker ps` — the WHOAMI\_NAME each echoes is the app's `name`, without the replica suffix. |
| <a name="output_runcmd"></a> [runcmd](#output\_runcmd) | Cloud-init runcmd blocks that start the containers. Feed straight into the Traefik child's `extra_runcmd` — the child must be the gateway on the SAME VM, since discovery is over the local Docker socket. |
| <a name="output_service_names"></a> [service\_names](#output\_service\_names) | Traefik service names the containers' labels declare (the `traefik.http.services.<name>` segment), so a caller can point a file router at a service it knows exists. |
<!-- END_TF_DOCS -->
