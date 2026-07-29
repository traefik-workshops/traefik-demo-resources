terraform {
  required_version = ">= 1.3"
  required_providers {
    # Official HPE provider (Morpheus resources live under the hpe_morpheus_*
    # prefix) — the successor of the deprecated gomorpheus/morpheus provider
    # (community EOL Aug 2026). Verified against v1.5.0.
    hpe = {
      source  = "HPE/hpe"
      version = "~> 1.5"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
