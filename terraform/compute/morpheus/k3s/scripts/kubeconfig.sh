#!/usr/bin/env bash
# external data source: SSH to the k3s VM and read /etc/rancher/k3s/k3s.yaml,
# rewriting 127.0.0.1 to the VM's IP. Retries until k3s has written the file
# (first boot) or the timeout elapses. stdin: {host, user, private_key,
# timeout}; stdout: {"kubeconfig_b64": "<base64>"}.
set -euo pipefail

eval "$(jq -r '@sh "HOST=\(.host) SSH_USER=\(.user) PRIVATE_KEY=\(.private_key) TIMEOUT=\(.timeout)"')"

keyfile="$(mktemp)"
trap 'rm -f "$keyfile"' EXIT
printf '%s\n' "$PRIVATE_KEY" >"$keyfile"
chmod 600 "$keyfile"

deadline=$(($(date +%s) + TIMEOUT))
raw=""
while true; do
  if raw="$(ssh -i "$keyfile" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR \
    "$SSH_USER@$HOST" 'cat /etc/rancher/k3s/k3s.yaml' 2>/dev/null)" && [ -n "$raw" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "timed out after ${TIMEOUT}s waiting for /etc/rancher/k3s/k3s.yaml on $SSH_USER@$HOST (is the VM up? does the template accept the key?)" >&2
    exit 1
  fi
  sleep 5
done

printf '%s' "$raw" | sed "s/127\.0\.0\.1/$HOST/g" | base64 | tr -d '\n' |
  jq -R '{kubeconfig_b64: .}'
