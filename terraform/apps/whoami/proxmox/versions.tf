terraform {
  # 1.4+ for terraform_data with provisioners (the LXC pct-exec install).
  required_version = ">= 1.4"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # 0.x — no stable major to `~>` onto yet; the ceiling guards against the
      # eventual 1.0 breaking sweep (repo rule for non-semver-stable providers).
      version = ">= 0.60.0, < 1.0.0"
    }
  }
}
