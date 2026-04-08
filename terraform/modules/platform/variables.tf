variable "name_prefix" {
  type = string
}

variable "enable_kms_hardening" {
  type = bool
}

variable "s3_kms_key_arn" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "external_secrets_namespace" {
  type = string
}

variable "external_secrets_service_account_name" {
  type = string
}

variable "external_secrets_secret_arns" {
  type = list(string)
}

variable "dagster_namespace" {
  type = string
}

variable "dagster_service_account_name" {
  type = string
}

variable "common_tags" {
  type = map(string)
}
