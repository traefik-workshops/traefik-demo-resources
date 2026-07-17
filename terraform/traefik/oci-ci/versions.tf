terraform {
  required_version = ">= 1.4" # terraform_data needs 1.4
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
