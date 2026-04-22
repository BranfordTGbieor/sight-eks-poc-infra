resource "grafana_folder" "alerting" {
  title = var.alert_folder_title
}

resource "grafana_contact_point" "exercise_slack" {
  name               = "Sight PoC Exercise Slack"
  disable_provenance = var.disable_provenance

  slack {
    url   = var.slack_webhook_url
    title = "{{ if eq .Status \"firing\" }}:rotating_light: Dagster job failure{{ else }}:white_check_mark: Dagster job recovered{{ end }} · {{ .CommonLabels.job }}"
    text  = <<-EOT
      {{- if gt (len .Alerts.Firing) 0 -}}
      *Status:* FIRING
      {{- else -}}
      *Status:* RESOLVED
      {{- end }}
      *Service:* {{ .CommonLabels.service }}
      *Job:* {{ .CommonLabels.job }}
      *Severity:* {{ .CommonLabels.severity }}

      {{- range .Alerts.Firing }}
      *Summary:* {{ index .Annotations "summary" }}
      *Details:* {{ index .Annotations "description" }}
      *Detected failures in last 5m:* {{ index .Annotations "failure_count" }}
      *Cluster:* {{ index .Annotations "cluster" }}
      *Namespace:* {{ index .Annotations "namespace" }}
      {{- end }}

      {{- if gt (len .Alerts.Resolved) 0 }}
      {{- range .Alerts.Resolved }}
      *Resolved:* {{ index .Annotations "summary" }}
      {{- end }}
      {{- end }}
    EOT
  }
}

resource "grafana_notification_policy" "root" {
  disable_provenance = var.disable_provenance

  contact_point   = grafana_contact_point.exercise_slack.name
  group_by        = ["alertname"]
  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"

  policy {
    contact_point   = grafana_contact_point.exercise_slack.name
    group_by        = ["alertname"]
    group_wait      = "30s"
    group_interval  = "5m"
    repeat_interval = "4h"

    matcher {
      label = "service"
      match = "="
      value = "dagster"
    }
  }
}

resource "grafana_rule_group" "dagster" {
  name               = "Sight PoC Dagster Alerts"
  folder_uid         = grafana_folder.alerting.uid
  interval_seconds   = 60
  disable_provenance = var.disable_provenance

  rule {
    name      = "Dagster Job Failure"
    condition = "C"
    for       = "0s"

    no_data_state  = "OK"
    exec_err_state = "Error"

    labels = {
      service  = "dagster"
      severity = "warning"
      job      = var.dagster_job_name
    }

    annotations = {
      summary       = "Dagster job failure detected for ${var.dagster_job_name}"
      description   = "Dagster emitted RUN_FAILURE for ${var.dagster_job_name} in ${var.dagster_namespace}. Investigate recent user-code logs and the Dagster run timeline."
      failure_count = "{{ printf \"%.0f\" $values.A.Value }}"
      cluster       = var.cluster_name
      namespace     = var.dagster_namespace
    }

    data {
      ref_id         = "A"
      datasource_uid = var.loki_datasource_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        datasource = {
          type = "loki"
          uid  = var.loki_datasource_uid
        }
        editorMode    = "code"
        expr          = "sum(count_over_time({cluster=\"${var.cluster_name}\", namespace=\"${var.dagster_namespace}\", app_component=\"user-code\", source=\"kubernetes_pod\"} |= \"RUN_FAILURE\" |= \"${var.dagster_job_name}\" [5m]))"
        instant       = true
        intervalMs    = 1000
        maxDataPoints = 43200
        queryType     = "instant"
        refId         = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        conditions = [
          {
            evaluator = {
              params = [0, 0]
              type   = "gt"
            }
            operator = {
              type = "and"
            }
            query = {
              params = ["A"]
            }
            reducer = {
              params = []
              type   = "last"
            }
            type = "avg"
          }
        ]
        datasource = {
          name = "Expression"
          type = "__expr__"
          uid  = "__expr__"
        }
        expression    = "A"
        hide          = false
        intervalMs    = 1000
        maxDataPoints = 43200
        reducer       = "last"
        refId         = "B"
        type          = "reduce"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        expression = "$B > 0"
        refId      = "C"
        type       = "math"
      })
    }
  }
}
