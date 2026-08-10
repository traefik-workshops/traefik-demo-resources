terraform {
  # 1.4+ for terraform_data with provisioners (the WinRM one-shots ARE the
  # resource — there is no Hyper-V terraform provider in this stack).
  required_version = ">= 1.4"
  required_providers {
  }
}
