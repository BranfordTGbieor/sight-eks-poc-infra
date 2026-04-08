variable "name_prefix" {
  type = string
}

variable "enable_kms_hardening" {
  type = bool
}

variable "cloudwatch_logs_kms_key_arn" {
  type = string
}

variable "enable_flow_logs" {
  type = bool
}

variable "flow_log_retention" {
  type = number
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "public_subnet_azs" {
  type = list(string)
}

variable "private_subnet_azs" {
  type = list(string)
}

variable "eks_cluster_name" {
  type = string
}

variable "common_tags" {
  type = map(string)
}
