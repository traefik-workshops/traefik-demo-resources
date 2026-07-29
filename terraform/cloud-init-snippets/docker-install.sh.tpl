# Install Docker with whatever package manager the image ships (Amazon Linux 2023: dnf;
# older Amazon Linux: yum; Debian/Ubuntu: apt). The image may already include docker, in
# which case this is a no-op. NOTE: an apt-only install silently broke Amazon Linux
# spokes — docker was never installed, so the image pull hit "docker: command not found".
if ! command -v docker >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then dnf install -y docker || true
  elif command -v yum >/dev/null 2>&1; then yum install -y docker || true
  elif command -v apt-get >/dev/null 2>&1; then apt-get update || true; apt-get install -y docker.io || apt-get install -y docker-ce docker-ce-cli containerd.io || true
  fi
fi
systemctl enable --now docker || true
