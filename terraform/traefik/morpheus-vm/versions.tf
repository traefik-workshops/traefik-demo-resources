terraform {
  required_version = ">= 1.3"
  required_providers {
    # gomorpheus/morpheus latest major is 0.x (0.14.x at time of writing). NB: the
    # provider is community-deprecated in favor of the official HPE/hpe provider
    # (EOL announced for Aug 2026) — migrate this module when the repo adopts it.
    morpheus = {
      source  = "gomorpheus/morpheus"
      version = "~> 0.14"
    }
  }
}
