variable "cluster_name" {
  type = string
}

variable "enable_kms_hardening" {
  type = bool
}

variable "eks_secrets_kms_key_arn" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "cluster_subnet_ids" {
  type = list(string)
}

variable "endpoint_private_access" {
  type = bool
}

variable "endpoint_public_access" {
  type = bool
}

variable "endpoint_public_access_cidrs" {
  type = list(string)
}

variable "node_subnet_ids" {
  type = list(string)
}

variable "node_instance_type" {
  type = string
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "common_tags" {
  type = map(string)
}

variable "enable_ebs_csi_driver" {
  type = bool
}
