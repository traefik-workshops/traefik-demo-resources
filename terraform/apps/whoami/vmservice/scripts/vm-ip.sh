#!/usr/bin/env bash
# data "external" program: wait for a VM Service VirtualMachine's guest address.
#
#   stdin   {"kubectl": "kubectl --kubeconfig … --context …", "namespace": "…", "name": "…", "timeout": "600"}
#   stdout  {"ip": "10.0.0.5", "bios_uuid": "4221…", "instance_uuid": "5021…"}
#
# Three verdicts, on purpose:
#   * the object does not exist  -> empty fields, exit 0. That is a destroy-time plan (the VM
#                                   is already gone) or a plan before the first apply; failing
#                                   here would wedge both.
#   * it exists without an address -> poll every 10s up to `timeout`, then exit 1. A VM that
#                                   never gets an address is a real failure (no image, no
#                                   network, no IP pool) and must fail the apply loudly.
#   * kubectl itself fails        -> exit 1 immediately (wrong context, expired Supervisor
#                                   token), with kubectl's own message on stderr.
set -uo pipefail

eval "$(jq -r '@sh "KUBECTL=\(.kubectl) NS=\(.namespace) NAME=\(.name) TIMEOUT=\(.timeout)"')"

deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  if ! out=$($KUBECTL -n "$NS" get virtualmachine "$NAME" -o json 2>&1); then
    if echo "$out" | grep -qi "not found"; then
      echo '{"ip":"","bios_uuid":"","instance_uuid":""}'
      exit 0
    fi
    echo "vm-ip: kubectl failed for $NS/$NAME: $out" >&2
    exit 1
  fi
  ip=$(echo "$out" | jq -r '.status.network.primaryIP4 // .status.vmIp // empty')
  if [ -n "$ip" ]; then
    echo "$out" | jq -c '{ip: (.status.network.primaryIP4 // .status.vmIp), bios_uuid: (.status.biosUUID // ""), instance_uuid: (.status.instanceUUID // "")}'
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "vm-ip: $NS/$NAME has no status.network.primaryIP4 / status.vmIp after ${TIMEOUT}s (powerState: $(echo "$out" | jq -r '.status.powerState // "unknown"'))" >&2
    exit 1
  fi
  sleep 10
done
