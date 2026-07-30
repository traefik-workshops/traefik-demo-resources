terraform {
  required_version = ">= 1.3"
  required_providers {
    # kubectl, not kubernetes: kubevirt.io/v1 VirtualMachine is a CRD type, and
    # kubectl_manifest applies it without needing the CRD to exist at plan time.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}
