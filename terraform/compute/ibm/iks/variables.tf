variable "cluster_name" {
  type        = string
  description = "IKS cluster name."
}

variable "kube_version" {
  type        = string
  default     = ""
  description = "IKS Kubernetes version (e.g. 1.32.3). Empty = the IKS default version at create time."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Existing VPC subnet IDs the cluster joins (e.g. compute/ibm/vpc's subnet_ids). One zone entry per subnet; all subnets must belong to the same VPC. The region comes from the configured ibm provider."
}

variable "resource_group_id" {
  type        = string
  default     = ""
  description = "Resource group ID the cluster lands in. Empty = the account's default resource group."
}

variable "cluster_node_count_per_zone" {
  type        = number
  default     = 1
  description = "Number of worker nodes PER ZONE (IKS semantics — one per subnet zone; two subnets x 1 = 2 workers)."
}

variable "cluster_node_type" {
  type        = string
  default     = "bx2.4x16"
  description = "Worker node flavor (4 vCPU / 16 GB — the smallest VPC gen2 flavor IKS reliably accepts)."
}

variable "wait_till" {
  type        = string
  default     = "OneWorkerNodeReady"
  description = "Readiness gate the create blocks on (MasterNodeReady | OneWorkerNodeReady | IngressReady | Normal). The default unblocks as soon as one worker is schedulable."
}
