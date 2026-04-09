variable "grafana_url" {
  description = "Grafana Cloud stack URL, for example https://<stack>.grafana.net."
  type        = string
}

variable "grafana_auth" {
  description = "Grafana service account token with alerting provisioning permissions."
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for the first Grafana contact point."
  type        = string
  sensitive   = true
}

variable "loki_datasource_uid" {
  description = "UID of the Grafana Cloud Loki data source used for Dagster failure alerts."
  type        = string
}

variable "alert_folder_title" {
  description = "Folder title used to store provisioned Grafana-managed alert rules."
  type        = string
  default     = "Hydrosat Alerting"
}

variable "dagster_job_name" {
  description = "Dagster job name used in the first failure alert."
  type        = string
  default     = "hydrosat_lakehouse_job"
}

variable "cluster_name" {
  description = "Cluster label used in the Loki query."
  type        = string
  default     = "hydrosat-dev-eks"
}

variable "dagster_namespace" {
  description = "Namespace label used in the Loki query."
  type        = string
  default     = "dagster"
}

variable "disable_provenance" {
  description = "Allow UI edits to provisioned alerting resources."
  type        = bool
  default     = false
}
