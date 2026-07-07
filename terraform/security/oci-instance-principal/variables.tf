variable "compartment_id" {
  type        = string
  description = "The OCID of the workload compartment whose instances the dynamic group matches."
}

variable "tenancy_id" {
  type        = string
  description = "Tenancy OCID (root compartment). OCI dynamic groups and their policies are tenancy-level and MUST live in the root compartment."
}

variable "home_region" {
  type        = string
  description = "Tenancy home region identifier (e.g. us-ashburn-1). OCI IAM writes only succeed against the home region, so the dynamic group + policy are created there via the OCI CLI."
}
