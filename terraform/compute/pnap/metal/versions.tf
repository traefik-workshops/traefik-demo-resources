terraform {
  required_version = ">= 1.3"

  required_providers {
    pnap = {
      source  = "phoenixnap/pnap"
      version = "~> 0.33"
    }
  }
}
