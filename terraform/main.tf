locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "hydrosat-take-home"
    },
    var.extra_tags,
  )
}

module "network" {
  source = "./modules/network"

  name_prefix          = local.name
  enable_kms_hardening = var.enable_service_kms_hardening
  enable_flow_logs     = var.enable_vpc_flow_logs
  flow_log_retention   = var.vpc_flow_log_retention_in_days
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_azs    = var.public_subnet_azs
  private_subnet_azs   = var.private_subnet_azs
  eks_cluster_name     = "${local.name}-eks"
  common_tags          = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name                 = "${local.name}-eks"
  cluster_version              = var.eks_cluster_version
  enable_kms_hardening         = var.enable_service_kms_hardening
  vpc_id                       = module.network.vpc_id
  cluster_subnet_ids           = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_private_access      = var.cluster_endpoint_private_access
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  node_subnet_ids              = module.network.private_subnet_ids
  node_instance_type           = var.node_instance_type
  node_desired_size            = var.node_desired_size
  node_min_size                = var.node_min_size
  node_max_size                = var.node_max_size
  enable_ebs_csi_driver        = var.enable_ebs_csi_driver
  common_tags                  = local.common_tags
}

module "platform" {
  source = "./modules/platform"

  name_prefix                           = local.name
  enable_kms_hardening                  = var.enable_service_kms_hardening
  oidc_provider_arn                     = module.eks.oidc_provider_arn
  oidc_provider_url                     = module.eks.oidc_provider_url
  external_secrets_namespace            = var.external_secrets_namespace
  external_secrets_service_account_name = var.external_secrets_service_account_name
  dagster_namespace                     = var.dagster_namespace
  dagster_service_account_name          = var.dagster_service_account_name
  external_secrets_secret_arns = compact([
    module.rds.master_user_secret_arn,
    var.grafana_cloud_secret_arn,
  ])
  common_tags = local.common_tags
}

module "rds" {
  source = "./modules/rds"

  name_prefix                 = local.name
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  allowed_security_group      = module.eks.node_security_group_id
  db_name                     = var.db_name
  db_username                 = var.db_username
  db_instance_class           = var.db_instance_class
  engine_version              = var.db_engine_version
  allocated_storage           = var.db_allocated_storage
  max_allocated_storage       = var.db_max_allocated_storage
  multi_az                    = var.db_multi_az
  skip_final_snapshot         = var.db_skip_final_snapshot
  enable_performance_insights = var.db_enable_performance_insights
  enable_enhanced_monitoring  = var.db_enable_enhanced_monitoring
  common_tags                 = local.common_tags
}
