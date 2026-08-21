#!/usr/bin/env bash
# Attach vCenter tags to a VM Service VM, located by BIOS uuid.
#
#   env  GOVC_URL / GOVC_USERNAME / GOVC_PASSWORD / GOVC_INSECURE   (govc's own)
#        VM_UUID        the VM's BIOS uuid (status.biosUUID on the VirtualMachine)
#        TAG_CATEGORY   the vCenter tag category the tags live in
#        TAGS           space-separated tag NAMES to attach
#        ATTACH_TIMEOUT seconds to wait for the vCenter object (default 300)
#
# By uuid, never by name: vCenter VM names are unique per FOLDER only, and a clone-provisioned
# sibling in another folder can legitimately carry the same name. Idempotent: a tag the VM
# already carries is skipped, so a re-run after a service-list change only adds.
set -uo pipefail

: "${VM_UUID:?VM_UUID is required}" "${TAG_CATEGORY:?TAG_CATEGORY is required}" "${TAGS:?TAGS is required}"
command -v govc >/dev/null || { echo "tag: govc is required on the machine running terraform" >&2; exit 1; }

deadline=$(( $(date +%s) + ${ATTACH_TIMEOUT:-300} ))
moref=""
# The caller already waited for the guest address, so the vCenter object exists; the retry
# covers inventory reads that lag vm-operator by a few seconds.
while [ -z "$moref" ]; do
  moref=$(govc vm.info -vm.uuid="$VM_UUID" -json 2>/dev/null | jq -r '(.virtualMachines // .VirtualMachines // [])[0] | (.self // .Self // {}) | (.value // .Value // empty)')
  if [ -z "$moref" ]; then
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "tag: no vCenter VM with BIOS uuid $VM_UUID after ${ATTACH_TIMEOUT:-300}s" >&2
      exit 1
    fi
    sleep 5
  fi
done
obj="VirtualMachine:$moref"

attached=$(govc tags.attached.ls -r "$obj" 2>/dev/null || true)
for tag in $TAGS; do
  if echo "$attached" | grep -qx "$tag"; then
    echo "tag: $obj already carries $TAG_CATEGORY/$tag"
    continue
  fi
  govc tags.attach -c "$TAG_CATEGORY" "$tag" "$obj" || { echo "tag: attaching $TAG_CATEGORY/$tag to $obj failed" >&2; exit 1; }
  echo "tag: attached $TAG_CATEGORY/$tag to $obj"
done
