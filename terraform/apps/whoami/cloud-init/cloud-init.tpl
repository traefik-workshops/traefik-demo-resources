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
      After=network.target docker.service
      Requires=docker.service

      [Service]
      # A leftover container from a previous boot would collide on --name; the
      # `-` prefix makes the rm a no-op when nothing is there.
      ExecStartPre=-/usr/bin/docker rm -f whoami
      ExecStart=/usr/bin/docker run --rm --name whoami --platform linux/${arch} -p ${port}:80%{ for k, v in environment } -e "${k}=${v}"%{ endfor } ${image} --verbose
      ExecStop=/usr/bin/docker stop whoami
      Restart=always

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

  # Wait for Docker to be ready, then pre-pull the whoami image as one fail-fast
  # block — a bad pull surfaces in `cloud-init status` instead of silently leaving
  # whoami.service crash-looping on the pull at start.
  - |
    set -euo pipefail
    for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; echo "waiting for docker ($i)"; sleep 2; done
    echo "Pulling ${image} (linux/${arch})"
    # Retry the pull (~4 min): the instance can boot before its NAT gateway is ready
    # (private-subnet spokes), so an early pull failure usually just means egress isn't up.
    for i in $(seq 1 20); do
      docker pull --platform linux/${arch} ${image} && break
      echo "Retrying whoami image pull ($i/20)..."
      sleep 10
    done

  # Start Service
  - systemctl daemon-reload
  - systemctl enable --now whoami.service

  # Signal readiness
  - echo "Whoami provisioning complete"
