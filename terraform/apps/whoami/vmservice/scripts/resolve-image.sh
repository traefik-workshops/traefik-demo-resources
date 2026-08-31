#!/usr/bin/env bash
# data "external": resolve a VM Service image's DESCRIPTIVE name (the content-library item name,
# surfaced on a VirtualMachineImage's status.imageName) to the RESOURCE name terraform must set on
# the IMMUTABLE spec.imageName. v1alpha2+ (VCF 9) names the VirtualMachineImage by the descriptive
# name (so it resolves to itself); v1alpha1 (vSphere 8U2) names it vmi-<hash> and carries the
# descriptive name only in status.imageName. One resolver serves both Supervisor generations.
#
#   stdin  {"kubectl": "kubectl --kubeconfig … --context …", "namespace": "…", "image_name": "…"}
#   stdout {"name": "<VirtualMachineImage metadata.name>"}   (falls back to image_name if unresolved)
set -uo pipefail
eval "$(jq -r '@sh "KUBECTL=\(.kubectl) NS=\(.namespace) IMG=\(.image_name)"')"
name=$($KUBECTL -n "$NS" get virtualmachineimages -o json 2>/dev/null | jq -r --arg img "$IMG" '
  ( [.items[] | select(.metadata.name == $img)]
  + [.items[] | select(.status.imageName == $img)] )
  | (.[0].metadata.name // empty)')
printf '{"name": "%s"}\n' "${name:-$IMG}"
