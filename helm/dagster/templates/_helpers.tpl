{{- define "sight-poc-dagster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sight-poc-dagster.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "sight-poc-dagster.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "sight-poc-dagster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "sight-poc-dagster.databaseSecretName" -}}
{{- if .Values.database.secretName -}}
{{- .Values.database.secretName -}}
{{- else -}}
{{- printf "%s-db" (include "sight-poc-dagster.fullname" .) -}}
{{- end -}}
{{- end -}}
