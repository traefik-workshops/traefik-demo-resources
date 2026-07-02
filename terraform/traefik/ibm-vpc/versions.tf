terraform {
  required_version = ">= 1.3"
  required_providers {
    # NEW PROVIDER for this repo: first IBM Cloud modules (justified — no
    # existing provider covers IBM). Pinned to the current major.
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "~> 1.89"
    }
  }
}
