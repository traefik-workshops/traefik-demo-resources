terraform {
  required_version = ">= 1.3"
  required_providers {
    # random: a per-execution suffix on the service-account id, so GCP's refusal to
    # immediately reuse a deleted account name cannot block a rebuild (main.tf).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
