terraform {
  required_version = ">= 1.3"
  required_providers {
    # kubectl, not kubernetes: vmoperator.vmware.com VirtualMachine is a CRD type, and
    # kubectl_manifest applies it without needing the CRD to exist at plan time.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
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
