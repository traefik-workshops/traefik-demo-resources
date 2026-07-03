terraform {
  required_version = ">= 1.3"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # 0.x — no stable major to `~>` onto yet; the ceiling guards against the
      # eventual 1.0 breaking sweep (repo rule for non-semver-stable providers).
      version = ">= 0.60.0, < 1.0.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
  }
}
