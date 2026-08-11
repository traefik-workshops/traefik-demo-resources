#cloud-config
# Demo Studio recording workstation (Phase A: vanilla Ubuntu 24.04 + cloud-init).
# GNOME + xrdp on a dummy Xorg pinned to ${rdp_resolution}, the dev toolchain, and the recording
# stack. Heavy install runs from /opt/studio/provision.sh with retry loops; log at
# /var/log/studio-provision.log. First-boot validation (per the plan): confirm the pinned display
# renders Grafana/Copilot smoothly before relying on capture.

ssh_pwauth: true

users:
  - name: ${admin_username}
    groups: [sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false

chpasswd:
  expire: false
  list:
    - ${admin_username}:${admin_password}

write_files:
  - path: /etc/ssh/sshd_config.d/99-studio.conf
    permissions: "0644"
    content: |
      PasswordAuthentication yes

  # Pin the virtual display to ${rdp_resolution} with the dummy driver (frame-exact, immune to
  # client renegotiation). ffmpeg x11grab captures this display; RDP is watch-only.
  - path: /etc/X11/xorg-dummy.conf
    permissions: "0644"
    content: |
      Section "Device"
        Identifier "dummy"
        Driver "dummy"
        VideoRam 256000
      EndSection
      Section "Monitor"
        Identifier "monitor"
        HorizSync 5.0-1000.0
        VertRefresh 5.0-200.0
        Modeline "${rdp_resolution}_60.0" 173.00 ${split("x", rdp_resolution)[0]} 2048 2248 2576 ${split("x", rdp_resolution)[1]} 1083 1088 1120 -hsync +vsync
      EndSection
      Section "Screen"
        Identifier "screen"
        Device "dummy"
        Monitor "monitor"
        DefaultDepth ${rdp_color_depth}
        SubSection "Display"
          Depth ${rdp_color_depth}
          Modes "${rdp_resolution}_60.0"
        EndSubSection
      EndSection

  # Persistent Xorg on :10 with the dummy driver.
  - path: /etc/systemd/system/studio-xorg.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Studio pinned Xorg (:10, dummy)
      After=systemd-user-sessions.service
      [Service]
      ExecStart=/usr/bin/Xorg :10 -config /etc/X11/xorg-dummy.conf -noreset
      Restart=always
      [Install]
      WantedBy=multi-user.target

  # A GNOME session on the pinned display, owned by the operator user.
  - path: /etc/systemd/system/studio-session.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Studio XFCE session on :10
      After=studio-xorg.service
      Requires=studio-xorg.service
      [Service]
      User=${admin_username}
      Environment=DISPLAY=:10
      Environment=XDG_RUNTIME_DIR=/run/user/1000
      ExecStartPre=/bin/sleep 3
      # XFCE (not GNOME): GNOME Shell crashes on a headless/software-GL dummy Xorg ("Oh no…").
      # XFCE renders fine without a GPU and xfwm4 is EWMH-compliant (wmctrl/xdotool drive it).
      # dbus-run-session is REQUIRED — bare startxfce4 from a systemd unit gives a black screen.
      ExecStart=/usr/bin/dbus-run-session -- /usr/bin/startxfce4
      Restart=always
      [Install]
      WantedBy=multi-user.target

  # Kill notifications / screensaver / auto-update prompts so captures are clean.
  - path: /etc/dconf/db/local.d/00-studio-clean
    permissions: "0644"
    content: |
      [org/gnome/desktop/notifications]
      show-banners=false
      [org/gnome/desktop/screensaver]
      idle-activation-enabled=false
      lock-enabled=false
      [org/gnome/desktop/session]
      idle-delay=uint32 0
      [org/gnome/desktop/interface]
      enable-animations=false

  - path: /opt/studio/provision.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -x
      export DEBIAN_FRONTEND=noninteractive
      retry(){ for i in $(seq 1 30); do "$@" && return 0; sleep 10; done; echo "FAILED: $*"; return 1; }

      retry apt-get update
      # Base desktop + xrdp + dummy driver + the recording stack.
      retry apt-get install -y --no-install-recommends \
        xfce4 xfce4-terminal xfce4-goodies dbus-x11 x11vnc \
        xrdp xorgxrdp xserver-xorg-video-dummy \
        curl wget git jq unzip ca-certificates gnupg apt-transport-https tmux
%{ if enable_recording_toolchain ~}
      # mesa-vulkan-drivers = software Vulkan (lavapipe) so Warp renders on a GPU-less VM.
      retry apt-get install -y --no-install-recommends ffmpeg wmctrl xdotool imagemagick mesa-vulkan-drivers
      # Warp terminal — recordings drive its no-account "Just use the terminal" mode.
      retry bash -c 'wget -qO- https://releases.warp.dev/linux/keys/warp.asc | gpg --dearmor > /usr/share/keyrings/warpdotdev.gpg'
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main" > /etc/apt/sources.list.d/warpdotdev.list
      retry apt-get update
      retry apt-get install -y warp-terminal || echo "WARN warp"
%{ endif ~}

      # Node (for the studio slide renderer) + Python venv tooling.
      retry bash -c 'curl -fsSL https://deb.nodesource.com/setup_22.x | bash -'
      retry apt-get install -y nodejs python3-venv python3-pip

%{ if dev_toolchain.docker ~}
      retry apt-get install -y docker.io containerd
      usermod -aG docker ${admin_username} || true
      systemctl enable --now docker || true
%{ endif ~}
%{ if dev_toolchain.chrome ~}
      retry bash -c 'wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb'
      retry apt-get install -y /tmp/chrome.deb
%{ endif ~}
%{ if dev_toolchain.vscode ~}
      retry bash -c 'wget -qO /tmp/code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"'
      retry apt-get install -y /tmp/code.deb
%{ endif ~}
%{ if dev_toolchain.postman ~}
      # snapd may still be settling on first boot; cap both waits so a stuck
      # snapd can never block the desktop session / k8s tools that follow.
      timeout 90 snap wait system seed.loaded 2>/dev/null || true
      timeout 240 snap install postman 2>/dev/null || echo "WARN postman skipped (snap not ready)"
%{ endif ~}
%{ if dev_toolchain.bruno ~}
      retry bash -c 'wget -qO /tmp/bruno.deb "https://github.com/usebruno/bruno/releases/latest/download/bruno_amd64_linux.deb" || true'
      apt-get install -y /tmp/bruno.deb || echo "WARN bruno"
%{ endif ~}
%{ if dev_toolchain.gh ~}
      retry bash -c 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list'
      retry apt-get update && retry apt-get install -y gh
%{ endif ~}
%{ if dev_toolchain.terraform ~}
      retry bash -c 'wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list'
      retry apt-get update && retry apt-get install -y terraform
%{ endif ~}
%{ if dev_toolchain.az_cli ~}
      retry bash -c 'curl -sL https://aka.ms/InstallAzureCLIDeb | bash'
%{ endif ~}
%{ if dev_toolchain.gcloud ~}
      retry bash -c 'echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg'
      retry apt-get update && retry apt-get install -y google-cloud-cli
%{ endif ~}
%{ if dev_toolchain.aws_cli ~}
      retry bash -c 'curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && unzip -q -o /tmp/awscliv2.zip -d /tmp && /tmp/aws/install --update'
%{ endif ~}
%{ if dev_toolchain.eksctl ~}
      retry bash -c 'curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp && mv /tmp/eksctl /usr/local/bin/'
%{ endif ~}
%{ if dev_toolchain.helm ~}
      retry bash -c 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
%{ endif ~}
%{ if dev_toolchain.kubectl ~}
      retry bash -c 'curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && install -m0755 kubectl /usr/local/bin/kubectl && rm -f kubectl'
%{ endif ~}
%{ if dev_toolchain.k3d ~}
      retry bash -c 'curl -sL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash'
%{ endif ~}
%{ if dev_toolchain.k9s ~}
      retry bash -c 'curl -sL "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb" -o /tmp/k9s.deb && apt-get install -y /tmp/k9s.deb'
%{ endif ~}
%{ if dev_toolchain.kubectx ~}
      git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx || true
      ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx; ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
%{ endif ~}
%{ if dev_toolchain.krew ~}
      su - ${admin_username} -c 'set -x; cd /tmp && curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz" && tar zxf krew-linux_amd64.tar.gz && ./krew-linux_amd64 install krew' || echo "WARN krew"
%{ endif ~}
%{ if dev_toolchain.claude_code ~}
      retry npm install -g @anthropic-ai/claude-code || echo "WARN claude-code"
%{ endif ~}
%{ if dev_toolchain.claude_desktop ~}
      echo "NOTE: Claude Desktop for Linux — install manually (no stable apt channel yet)"
%{ endif ~}

      # dconf clean-desk profile
      dconf update || true

      # xrdp uses the Xorg backend (xorgxrdp); the pinned :10 session is separate for capture.
      systemctl enable --now xrdp || true
      systemctl daemon-reload
      systemctl enable --now studio-xorg.service studio-session.service || true

      # mask unattended-upgrades so no update prompts fire mid-capture
      systemctl mask unattended-upgrades apt-daily.service apt-daily-upgrade.service || true
      echo "studio provision complete"

%{ if git_deploy_key != "" ~}
  - path: /home/${admin_username}/.ssh/id_ed25519
    owner: ${admin_username}:${admin_username}
    permissions: "0600"
    content: |
      ${indent(6, git_deploy_key)}
  - path: /home/${admin_username}/.ssh/config
    owner: ${admin_username}:${admin_username}
    permissions: "0600"
    content: |
      Host github.com
        IdentityFile ~/.ssh/id_ed25519
        StrictHostKeyChecking accept-new
%{ endif ~}
%{ for f in extra_files ~}
  - path: ${f.path}
    permissions: "${f.permissions}"
    content: |
      ${indent(6, f.content)}
%{ endfor ~}

runcmd:
  - [ bash, -c, "mkdir -p /run/user/1000 && chown ${admin_username}:${admin_username} /run/user/1000" ]
  - [ bash, -c, "bash /opt/studio/provision.sh 2>&1 | tee /var/log/studio-provision.log" ]
%{ if git_deploy_key != "" ~}
  - [ bash, -c, "su - ${admin_username} -c 'git clone ${git_repo_url} ~/traefik-demo || git -C ~/traefik-demo pull' 2>&1 | tee -a /var/log/studio-provision.log" ]
%{ endif ~}
