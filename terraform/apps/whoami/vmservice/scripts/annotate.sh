#!/usr/bin/env bash
# Write a VM Service VM's Notes (config.annotation), the VM located by BIOS uuid.
#
#   env  GOVC_URL / GOVC_USERNAME / GOVC_PASSWORD / GOVC_INSECURE   (govc's own)
#        VM_UUID        the VM's BIOS uuid (status.biosUUID on the VirtualMachine)
#        ANNOTATION     the full Notes text: the line-format traefik.<key>=<value> block
#        ATTACH_TIMEOUT seconds to wait for the vCenter object (default 300)
#
# By uuid, never by name: vCenter VM names are unique per FOLDER only, and a clone-provisioned
# sibling in another folder can legitimately carry the same name. Idempotent by construction:
# `vm.change -annotation` REPLACES the Notes, so a re-run converges on the rendered block.
set -uo pipefail

: "${VM_UUID:?VM_UUID is required}" "${ANNOTATION:?ANNOTATION is required}"
command -v govc >/dev/null || { echo "annotate: govc is required on the machine running terraform" >&2; exit 1; }

deadline=$(( $(date +%s) + ${ATTACH_TIMEOUT:-300} ))
# The caller already waited for the guest address, so the vCenter object exists; the retry
# covers inventory reads that lag vm-operator by a few seconds.
until govc vm.info -vm.uuid="$VM_UUID" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "annotate: no vCenter VM with BIOS uuid $VM_UUID after ${ATTACH_TIMEOUT:-300}s" >&2
    exit 1
  fi
  sleep 5
done

govc vm.change -vm.uuid="$VM_UUID" -annotation="$ANNOTATION" || { echo "annotate: writing the Notes of $VM_UUID failed" >&2; exit 1; }
echo "annotate: wrote $(printf '%s\n' "$ANNOTATION" | grep -c .) Notes line(s) to $VM_UUID"
