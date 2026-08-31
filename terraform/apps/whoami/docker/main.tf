# whoami as plain Docker containers — the container leg for the demos whose platform has
# no managed container service to borrow. AWS has ECS, Azure has ACI, OCI and Alibaba have
# Container Instances, Proxmox has LXC; vSphere, GCE and Morpheus have nothing of the kind,
# so the container runtime IS Docker and the discovery mechanism is core Traefik's docker
# provider reading the local socket.
#
# TEMPLATE-ONLY, like apps/whoami/cloud-init: this module owns no resources. It renders a
# cloud-init runcmd FRAGMENT that the caller feeds to its Traefik child's `extra_runcmd`.
# That is not a shortcut, it is forced by the topology. The containers have to live on the
# SAME machine as the gateway that discovers them, because `--providers.docker` talks to
# /var/run/docker.sock and a socket is not a network endpoint. Terraform could only own
# them through the kreuzwerker/docker provider, whose `host` would be the gateway VM's
# address — UNKNOWN at plan time on a first apply, and an unknown provider argument is a
# hard plan error, not something the demos' two-pass `make up` can paper over.
#
# apps/AGENTS.md flags template-only modules as unusual and asks that the pattern not
# spread. This one earns it: three callers (vsphere, gcp, morpheus), no provider can own
# the objects, and the alternative is the same shell script pasted into three demos.

locals {
  # A tag is a `:` in the LAST path segment (a registry host may carry a :port) —
  # identical inference to apps/whoami/cloud-init/main.tf.
  image_last_segment = element(split("/", var.whoami_image), length(split("/", var.whoami_image)) - 1)
  image              = length(regexall(":", local.image_last_segment)) > 0 ? var.whoami_image : "${var.whoami_image}:${var.whoami_version}"

  # "<app>-<n>" keys, the scheme every whoami sibling uses, so a caller reading
  # container_names sees the same shape as an ec2/gce/vsphere instances map.
  containers = flatten([
    for app_name, app in var.apps : [
      for idx in range(app.replicas) : {
        key  = "${app_name}-${idx + 1}"
        name = "${try(app.name, app_name)}-${idx + 1}"

        # WHOAMI_NAME first so the caller's `environment` can still override it; the
        # value is what the response body echoes as `Name:`, which is the exact string
        # the scenario suite asserts on.
        environment = merge(
          try(app.name, "") != "" ? { WHOAMI_NAME = app.name } : {},
          var.environment,
          try(app.environment, {}),
        )

        # Traefik labels are the discovery config here — the docker provider's equivalent
        # of EC2's dotted tags or GCE's `traefik` metadata item. Every replica carries the
        # SAME service label, which is what makes them servers of one service rather than
        # N single-server services.
        labels = merge(var.common_labels, try(app.traefik_labels, {}))
      }
    ]
  ])

  # The OTLP collector these whoamis export to is typically a LAB-INTERNAL hostname
  # (e.g. collector.<domain>) that resolves on the VM via lab DNS but NOT inside a
  # bridge-networked container: a container inherits the docker daemon's resolver, which on a
  # systemd-resolved host is a stub address the daemon cannot use, so it silently falls back to
  # a public resolver that cannot see lab DNS. The exporter then fails and the leg reports no
  # telemetry (the gateway, on --network host, is unaffected — which is why only the container
  # backend goes dark in the service graph). Pull the endpoint host out so the runcmd can
  # resolve it on the VM, where lab DNS works, and pin it into each container via --add-host.
  otlp_endpoint = try(var.environment["OTEL_EXPORTER_OTLP_ENDPOINT"], "")
  otlp_host     = local.otlp_endpoint != "" ? try(regex("^[a-zA-Z]+://([^:/]+)", local.otlp_endpoint)[0], "") : ""

  # Rendered once: the caller passes this straight into extra_runcmd, and cloud-init runs
  # it after Docker is installed and before the gateway starts.
  runcmd = templatefile("${path.module}/run-containers.sh.tpl", {
    containers = local.containers
    image      = local.image
    otlp_host  = local.otlp_host
  })
}
