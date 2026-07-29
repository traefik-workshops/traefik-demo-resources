terraform {
  required_version = ">= 1.4" # terraform_data needs 1.4
  required_providers {
    # Official HPE provider (Morpheus resources live under the hpe_morpheus_*
    # prefix) — the successor of the deprecated gomorpheus/morpheus provider
    # (community EOL Aug 2026). Verified against v1.5.0.
  }
}
