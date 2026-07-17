#!/usr/bin/env bash
# git-config-sync — pull this gateway's file-provider dynamic config from the hub's git server
# and drop it into Traefik's watch dir. Run once at boot (the boot gate) and then on a timer;
# Traefik's --providers.file.watch hot-reloads on every change, so a `terraform` push reaches
# the gateway within one interval with NO VM replacement. See terraform/config-server/git.
#
# Template vars: repo_url (https://git.<domain>/config.git), gateway_name (the repo subdir),
# watch_dir (Traefik's --providers.file.directory), work_dir (local checkout).
set -u

REPO_URL="${repo_url}"
GATEWAY="${gateway_name}"
WATCH_DIR="${watch_dir}"
WORK_DIR="${work_dir}"
SRC="$WORK_DIR/$GATEWAY/dynamic.yaml"
DST="$WATCH_DIR/dynamic.yaml"

mkdir -p "$WATCH_DIR"

# Clone on first run, pull thereafter. The hub cert is the demo's real Let's Encrypt wildcard
# on the clouds/proxmox, but self-signed early in some boots — sslVerify off keeps the lab
# robust (config is non-secret and the path is the private lab net anyway).
export GIT_SSL_NO_VERIFY=true
if [ ! -d "$WORK_DIR/.git" ]; then
  rm -rf "$WORK_DIR"
  git clone --quiet "$REPO_URL" "$WORK_DIR" || { echo "git-config-sync: clone failed ($REPO_URL)"; exit 1; }
else
  git -C "$WORK_DIR" fetch --quiet origin && git -C "$WORK_DIR" reset --quiet --hard origin/main \
    || { echo "git-config-sync: pull failed"; exit 1; }
fi

# Publish only on a real change, and atomically (write-temp-then-rename) so Traefik never reads
# a half-written file. Absent source => this gateway has no config yet; leave the dir empty.
if [ -f "$SRC" ]; then
  if ! cmp -s "$SRC" "$DST" 2>/dev/null; then
    tmp="$(mktemp "$WATCH_DIR/.dynamic.XXXXXX")"
    cp "$SRC" "$tmp" && mv -f "$tmp" "$DST"
    echo "git-config-sync: updated $DST from $GATEWAY/dynamic.yaml"
  fi
else
  echo "git-config-sync: no $GATEWAY/dynamic.yaml in the repo yet (gateway not configured)"
fi
