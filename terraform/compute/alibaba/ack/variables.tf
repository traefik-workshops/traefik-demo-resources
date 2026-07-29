variable "cluster_name" {
  type        = string
  description = "ACK cluster name."
}

variable "ack_version" {
  type        = string
  default     = ""
  description = "ACK Kubernetes version. Empty = the latest version ACK offers at create time."
}

variable "cluster_spec" {
  type        = string
  default     = "ack.pro.small"
  description = "ACK managed cluster spec (ack.pro.small = Pro; some newer regions no longer offer the Basic ack.standard)."
}

variable "vswitch_ids" {
  type        = list(string)
  description = "Existing vswitch IDs the control plane and node pools join (e.g. compute/alibaba/vpc's vswitch_ids). The region comes from the configured alicloud provider."
}

variable "security_group_id" {
  type        = string
  default     = ""
  description = "Existing security group for the cluster's nodes. Empty = ACK creates one."
}

variable "cluster_node_count" {
  type        = number
  default     = 1
  description = "Number of nodes for the cluster."
}

variable "cluster_node_type" {
  type        = string
  default     = "ecs.c6.large"
  description = "Default ECS instance type for cluster nodes (2 vCPU / 4 GB — the smallest ACK reliably accepts)."
}

variable "node_disk_category" {
  type        = string
  default     = "cloud_essd"
  description = "System disk category for the nodes."
}

variable "node_disk_size" {
  type        = number
  default     = 40
  description = "System disk size (GB) for the nodes."
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod CIDR (Flannel). Must not overlap the VPC CIDR."
}

variable "service_cidr" {
  type        = string
  default     = "10.96.0.0/16"
  description = "Service CIDR. Must not overlap the VPC CIDR."
}

variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Create a NAT gateway + SNAT so nodes have outbound internet (image pulls). Disable when the vswitches already route through one."
}

variable "worker_nodes" {
  type = list(object({
    label = string
    taint = string
    count = number
  }))
  default     = []
  description = "Worker node pool definitions. Each entry creates a dedicated node pool with the given label and taint (ACK supports native taints, applied at the pool)."
}

variable "update_kubeconfig" {
  type        = bool
  default     = true
  description = "Update kubeconfig after cluster creation"
}
