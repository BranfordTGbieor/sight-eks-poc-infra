output "alert_folder_uid" {
  value       = grafana_folder.alerting.uid
  description = "Grafana folder UID for the provisioned Hydrosat alert rules."
}

output "contact_point_name" {
  value       = grafana_contact_point.exercise_email.name
  description = "Name of the provisioned contact point."
}
