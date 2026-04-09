variable "aws_region" {
  description = "AWS region used for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as the naming prefix."
  type        = string
  default     = "hydrosat"
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets."
  type        = list(string)
  default     = ["10.42.0.0/24", "10.42.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnets are required for a resilient internet-facing load balancer footprint."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnets are required for EKS worker nodes and RDS subnet groups."
  }
}

variable "public_subnet_azs" {
  description = "Availability zones for public subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_azs" {
  description = "Availability zones for private subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "eks_cluster_version" {
  description = "Pinned EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_private_access" {
  description = "Whether the EKS API server is reachable from inside the VPC."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server is reachable from the public internet."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint when enabled."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  description = "Managed node group instance type."
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum node count for the managed node group."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum node count for the managed node group."
  type        = number
  default     = 3
}

variable "enable_ebs_csi_driver" {
  description = "Whether to install the AWS EBS CSI driver as an EKS add-on."
  type        = bool
  default     = true
}

variable "dagster_namespace" {
  description = "Kubernetes namespace used for the Dagster platform."
  type        = string
  default     = "dagster"
}

variable "external_secrets_namespace" {
  description = "Kubernetes namespace used by External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account_name" {
  description = "Service account name used by External Secrets Operator."
  type        = string
  default     = "hydrosat-external-secrets"
}

variable "dagster_service_account_name" {
  description = "Service account name used by Dagster workloads."
  type        = string
  default     = "hydrosat-dagster"
}

variable "grafana_cloud_secret_arn" {
  description = "Optional AWS Secrets Manager ARN containing Grafana Cloud logs and metrics endpoints and credentials."
  type        = string
  default     = ""
}

variable "enable_service_kms_hardening" {
  description = "Whether to enable customer-managed KMS encryption for supported services. When enabled, explicit KMS key ARNs must also be provided."
  type        = bool
  default     = false
}

variable "eks_secrets_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used for EKS secret encryption."
  type        = string
  default     = ""
}

variable "cloudwatch_logs_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used for CloudWatch Logs encryption, including VPC flow logs."
  type        = string
  default     = ""
}

variable "s3_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used for S3 bucket encryption."
  type        = string
  default     = ""
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs for the demo environment."
  type        = bool
  default     = true
}

variable "vpc_flow_log_retention_in_days" {
  description = "CloudWatch retention for VPC Flow Logs."
  type        = number
  default     = 7
}

variable "db_name" {
  description = "Dagster metadata database name."
  type        = string
  default     = "dagster"
}

variable "db_username" {
  description = "Dagster metadata database username."
  type        = string
  default     = "dagster"
}

variable "db_instance_class" {
  description = "RDS instance class for Dagster metadata."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version for Dagster metadata. Using major version 16 lets AWS select an available minor release."
  type        = string
  default     = "16"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GiB for the Dagster metadata database."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum autoscaled storage in GiB for the Dagster metadata database."
  type        = number
  default     = 100
}

variable "db_multi_az" {
  description = "Whether to run the RDS instance in Multi-AZ mode. Disabled by default for the cost-conscious demo environment; enable for stronger production availability."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on destroy for the take-home environment."
  type        = bool
  default     = true
}

variable "db_enable_performance_insights" {
  description = "Whether to enable RDS Performance Insights."
  type        = bool
  default     = false
}

variable "db_enable_enhanced_monitoring" {
  description = "Whether to enable RDS Enhanced Monitoring."
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Additional tags applied to all supported resources."
  type        = map(string)
  default     = {}
}

check "kms_key_arns_when_enabled" {
  assert {
    condition = !var.enable_service_kms_hardening || (
      trimspace(var.eks_secrets_kms_key_arn) != "" &&
      trimspace(var.cloudwatch_logs_kms_key_arn) != "" &&
      trimspace(var.s3_kms_key_arn) != ""
    )

    error_message = "enable_service_kms_hardening requires explicit eks_secrets_kms_key_arn, cloudwatch_logs_kms_key_arn, and s3_kms_key_arn values."
  }
}
