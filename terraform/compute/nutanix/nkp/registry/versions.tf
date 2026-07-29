terraform {
  required_version = ">= 1.4" # terraform_data needs 1.4
  required_providers {
    nutanix = {
      source  = "nutanix/nutanix"
      version = ">= 2.4.0"
    }
  }
}
