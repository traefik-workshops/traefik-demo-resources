terraform {
  # 1.4+ for terraform_data with provisioners (via compute/hyperv/vm).
  required_version = ">= 1.4"
  required_providers {
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
