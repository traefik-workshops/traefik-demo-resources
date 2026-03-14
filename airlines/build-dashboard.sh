#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
tar czf "$SCRIPT_DIR/helm/files/dashboard-src.tar.gz" \
  -C "$SCRIPT_DIR/dashboard-app" \
  --exclude=node_modules --exclude=dist --exclude='.vite' .
echo "Updated helm/files/dashboard-src.tar.gz ($(wc -c < "$SCRIPT_DIR/helm/files/dashboard-src.tar.gz") bytes)"
