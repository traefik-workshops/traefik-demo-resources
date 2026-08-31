# Start the whoami containers the local Traefik child discovers over the Docker socket.
# POSIX sh: cloud-init runs runcmd blocks with /bin/sh, not bash.
set -eu

# Docker is already installed by the gateway's own preview-mode block (this fragment is
# injected after it), but the daemon can still be a second or two behind the install.
for i in $(seq 1 30); do
  docker info > /dev/null 2>&1 && break
  echo "Waiting for the Docker daemon ($i/30)..."
  sleep 2
done

# The OTLP collector is a lab-internal hostname the VM resolves via lab DNS but a bridge
# container cannot (docker's daemon resolver can't reach lab DNS on a systemd-resolved host),
# so the exporter would silently fail and this leg would report no telemetry. Resolve it here,
# on the VM, and pin host:ip into every container with --add-host so the export can land.
ADD_HOST=""
%{ if otlp_host != "" ~}
OTLP_IP=""
for i in $(seq 1 30); do
  OTLP_IP=$(getent hosts "${otlp_host}" 2>/dev/null | awk '{print $1; exit}')
  [ -n "$OTLP_IP" ] && break
  echo "Resolving OTLP collector ${otlp_host} ($i/30)..."
  sleep 2
done
if [ -n "$OTLP_IP" ]; then
  ADD_HOST="--add-host ${otlp_host}:$OTLP_IP"
  echo "OTLP collector ${otlp_host} -> $OTLP_IP (pinned into containers via --add-host)"
else
  echo "WARNING: could not resolve OTLP collector ${otlp_host} on the VM; this leg may report no telemetry"
fi
%{ endif ~}

# Retry the pull: these VMs reach the registry through NAT that may itself still be coming
# up on a first boot, and an unretried pull is the single most common cause of an empty
# leg. Same 20-try shape the sibling whoami cloud-init uses.
for i in $(seq 1 20); do
  docker pull "${image}" && break
  echo "Retrying whoami image pull ($i/20)..."
  sleep 15
done

%{ for c in containers ~}
# --- ${c.name} ---
# `docker rm -f` first so a re-run of this fragment is idempotent rather than a name clash.
docker rm -f ${c.name} > /dev/null 2>&1 || true
# --restart unless-stopped, NOT --rm: these have no systemd unit of their own, so this is
# the only thing that brings them back after a VM reboot. --verbose is mandatory, not
# cosmetic — whoami gates its OTLP access logs behind the flag and offers no env equivalent.
docker run -d --restart unless-stopped --name ${c.name} $ADD_HOST \
%{ for k, v in c.labels ~}
  --label "${k}=${v}" \
%{ endfor ~}
%{ for k, v in c.environment ~}
  -e "${k}=${v}" \
%{ endfor ~}
  "${image}" --verbose
%{ endfor ~}

# Deliberately no `-p`: the gateway container is --network host and already owns :80,
# :443, :8080 and :9443, so publishing would collide. The docker provider hands Traefik
# each container's own bridge IP (172.17.0.0/16), which the host dials directly.
docker ps --filter "label=traefik.enable=true" --format '  discovered: {{.Names}} {{.Status}}'
