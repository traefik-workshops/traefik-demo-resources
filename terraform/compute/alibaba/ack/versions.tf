terraform {
  required_version = ">= 1.3"
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.220"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
