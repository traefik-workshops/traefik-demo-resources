#!/usr/bin/env bash
# data "external": resolve a VM Service image's DESCRIPTIVE name (the content-library item name,
# surfaced on a VirtualMachineImage's status.imageName) to the RESOURCE name terraform must set on
# the IMMUTABLE spec.imageName. v1alpha2+ (VCF 9) names the VirtualMachineImage by the descriptive
# name (so it resolves to itself); v1alpha1 (vSphere 8U2) names it vmi-<hash> and carries the
# descriptive name only in status.imageName. One resolver serves both Supervisor generations.
#
# WHY THIS POLLS: host/setup-vm-service-image.sh publishes the library ITEM, but the Supervisor's
# content-library controller materialises the VirtualMachineImage CR ASYNCHRONOUSLY (seconds to a
# couple of minutes after the import returns). A fresh `apply` reads this data source at plan time
# and can outrun that reconcile. Resolving to the fallback then is UNRECOVERABLE: spec.imageName is
# immutable, so the VM is created with the wrong name, rejected VirtualMachineImageNotFound, never
# powers on, and every subsequent apply fails "error when patching" trying to change an immutable
# field. So WAIT for the CR to exist (bounded by timeout, default 900s), then resolve; fall back to
# the descriptive name only when it never appears — a destroy plan against a torn-down namespace,
# or a genuinely absent image (which then fails loudly at the VM create, not silently-wrong).
#
#   stdin  {"kubectl":"kubectl --kubeconfig … --context …","namespace":"…","image_name":"…","timeout":"900"}
#   stdout {"name": "<VirtualMachineImage metadata.name>"}   (falls back to image_name if unresolved)
set -uo pipefail
eval "$(jq -r '@sh "KUBECTL=\(.kubectl) NS=\(.namespace) IMG=\(.image_name) TIMEOUT=\(.timeout // "900")"')"

resolve() {
  $KUBECTL -n "$NS" get virtualmachineimages -o json 2>/dev/null | jq -r --arg img "$IMG" '
    ( [.items[] | select(.metadata.name == $img)]
    + [.items[] | select(.status.imageName == $img)] )
    | (.[0].metadata.name // empty)'
}

deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  name=$(resolve)
  [ -n "$name" ] && { printf '{"name": "%s"}\n' "$name"; exit 0; }
  [ "$(date +%s)" -ge "$deadline" ] && break
  sleep 5
done
printf '{"name": "%s"}\n' "$IMG"
