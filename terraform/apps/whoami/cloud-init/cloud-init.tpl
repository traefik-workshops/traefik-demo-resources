#cloud-config

ssh_pwauth: true
users:
  - name: traefiker
    groups: sudo
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false

chpasswd:
  expire: false
  list: |
    traefiker:topsecretpassword

write_files:
  - path: /etc/systemd/system/whoami.service
    content: |
      [Unit]
      Description=Traefik Whoami Service
      After=network.target

      [Service]
      # WHOAMI_NAME (when non-empty) → response shows `Name: <name>` so the audience
      # can tell which VM served them; empty = whoami uses OS hostname.
      Environment=WHOAMI_NAME=${name}
      ExecStart=/usr/local/bin/whoami --verbose --port ${port}
      Restart=always
      User=nobody
      AmbientCapabilities=CAP_NET_BIND_SERVICE

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: "0644"

runcmd:
  # Install Docker based on distribution
  - |
    if command -v apt-get >/dev/null; then
      apt-get update -y
      apt-get install -y docker.io
      systemctl start docker
      systemctl enable docker
    elif command -v yum >/dev/null; then
      yum update -y
      yum install -y docker
      systemctl start docker
      systemctl enable docker
    fi

  # Wait for Docker to be ready, then extract the whoami binary from the image as
  # one fail-fast block — a bad pull/extract surfaces in `cloud-init status` instead
  # of silently leaving no binary (which makes whoami.service crash-loop).
  - |
    set -euo pipefail
    for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; echo "waiting for docker ($i)"; sleep 2; done
    echo "Pulling traefik/whoami:${whoami_version} (linux/${arch})"
    # Retry the pull (~4 min): the instance can boot before its NAT gateway is ready
    # (private-subnet spokes), so an early pull failure usually just means egress isn't up.
    for i in $(seq 1 20); do
      docker pull --platform linux/${arch} traefik/whoami:${whoami_version} && break
      echo "Retrying whoami image pull ($i/20)..."
      sleep 10
    done
    cid=$(docker create --platform linux/${arch} traefik/whoami:${whoami_version})
    docker cp "$cid:/whoami" /usr/local/bin/whoami
    docker rm -v "$cid"
    chmod +x /usr/local/bin/whoami
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/whoami

  # Start Service
  - systemctl daemon-reload
  - systemctl enable --now whoami.service

  # Signal readiness
  - echo "Whoami provisioning complete"
