#!/usr/bin/env python3
"""Render GitOps and Helm inputs from the current Terraform state.

This script keeps live, environment-specific values out of source control by
rebuilding the Argo CD, External Secrets, Alloy, and Helm inputs from
Terraform outputs plus a small set of CI-provided environment variables.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
TF_DIR = ROOT_DIR / "terraform"

INFRA_REPO_URL = os.getenv("INFRA_REPO_URL", "REPLACE_WITH_GIT_REPOSITORY_URL")
GITOPS_TARGET_REVISION = os.getenv("GITOPS_TARGET_REVISION", "REPLACE_WITH_GIT_TARGET_REVISION")
GRAFANA_CLOUD_SECRET_ARN = os.getenv("GRAFANA_CLOUD_SECRET_ARN")


def terraform_outputs() -> dict[str, object]:
    """Return Terraform outputs as a flat key/value mapping."""
    result = subprocess.run(
        ["terraform", f"-chdir={TF_DIR}", "output", "-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    raw_outputs = json.loads(result.stdout)
    return {key: value["value"] for key, value in raw_outputs.items()}


def write_file(relative_path: str, content: str) -> None:
    """Write normalized UTF-8 content beneath the repo root."""
    path = ROOT_DIR / relative_path
    path.write_text(f"{content.rstrip()}\n", encoding="utf-8")


def main() -> None:
    """Materialize all live GitOps inputs required for bootstrap and sync."""
    if not GRAFANA_CLOUD_SECRET_ARN:
        raise SystemExit(
            "Set GRAFANA_CLOUD_SECRET_ARN to the AWS Secrets Manager ARN for Grafana Cloud observability credentials."
        )

    outputs = terraform_outputs()
    aws_region = outputs["aws_region"]
    cluster_name = outputs["cluster_name"]
    dagster_role_arn = outputs["dagster_service_account_role_arn"]
    external_secrets_role_arn = outputs["external_secrets_service_account_role_arn"]
    data_lake_bucket = outputs["data_lake_bucket_name"]
    rds_address = outputs["rds_address"]
    rds_secret_arn = outputs["rds_master_secret_arn"]

    write_file(
        "gitops/argocd/bootstrap/root-application.yaml",
        f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sight-poc-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: {INFRA_REPO_URL}
    targetRevision: {GITOPS_TARGET_REVISION}
    path: gitops/argocd/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
""",
    )

    write_file(
        "gitops/argocd/apps/sight-poc-dagster.yaml",
        f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sight-poc-dagster
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: sight-poc-platform
  source:
    repoURL: {INFRA_REPO_URL}
    targetRevision: {GITOPS_TARGET_REVISION}
    path: helm/dagster
    helm:
      valueFiles:
        - values-gitops.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dagster
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
""",
    )

    write_file(
        "gitops/argocd/apps/external-secrets-resources.yaml",
        f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sight-poc-external-secrets-resources
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: sight-poc-platform
  source:
    repoURL: {INFRA_REPO_URL}
    targetRevision: {GITOPS_TARGET_REVISION}
    path: gitops/external-secrets
  ignoreDifferences:
    - group: external-secrets.io
      kind: ExternalSecret
      jsonPointers:
        - /status
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
""",
    )

    write_file(
        "gitops/argocd/apps/external-secrets-operator.yaml",
        f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sight-poc-external-secrets-operator
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: sight-poc-platform
  sources:
    - repoURL: https://charts.external-secrets.io
      chart: external-secrets
      targetRevision: 2.2.0
      helm:
        releaseName: sight-poc-external-secrets
        valueFiles:
          - $values/gitops/argocd/values/external-secrets-values.yaml
    - repoURL: {INFRA_REPO_URL}
      targetRevision: {GITOPS_TARGET_REVISION}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
""",
    )

    write_file(
        "gitops/argocd/apps/monitoring-alloy.yaml",
        f"""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sight-poc-alloy
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: sight-poc-platform
  sources:
    - repoURL: https://grafana.github.io/helm-charts
      chart: alloy
      targetRevision: 1.5.3
      helm:
        releaseName: sight-poc-alloy
        valueFiles:
          - $values/gitops/argocd/values/alloy-values.yaml
    - repoURL: {INFRA_REPO_URL}
      targetRevision: {GITOPS_TARGET_REVISION}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
""",
    )

    write_file(
        "gitops/argocd/apps/project.yaml",
        f"""apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: sight-poc-platform
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  description: Sight PoC platform applications managed by Argo CD in the demo cluster
  sourceRepos:
    - {INFRA_REPO_URL}
    - https://grafana.github.io/helm-charts
    - https://charts.external-secrets.io
  destinations:
    - namespace: dagster
      server: https://kubernetes.default.svc
    - namespace: monitoring
      server: https://kubernetes.default.svc
    - namespace: external-secrets
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
""",
    )

    write_file(
        "gitops/argocd/values/external-secrets-values.yaml",
        f"""fullnameOverride: sight-poc-external-secrets

installCRDs: true

serviceAccount:
  create: true
  name: sight-poc-external-secrets
  annotations:
    eks.amazonaws.com/role-arn: {external_secrets_role_arn}

serviceMonitor:
  enabled: true
  namespace: monitoring

resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi
""",
    )

    write_file(
        "gitops/external-secrets/cluster-secret-store.yaml",
        f"""apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: sight-poc-aws-secretsmanager
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  provider:
    aws:
      service: SecretsManager
      region: {aws_region}
      auth:
        jwt:
          serviceAccountRef:
            name: sight-poc-external-secrets
            namespace: external-secrets
""",
    )

    write_file(
        "gitops/external-secrets/dagster-db-external-secret.yaml",
        f"""apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: sight-poc-dagster-db
  namespace: dagster
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: sight-poc-aws-secretsmanager
  target:
    name: sight-poc-dagster-db
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        username: "{{{{ .username }}}}"
        password: "{{{{ .password }}}}"
        host: "{rds_address}"
        port: "5432"
        dbname: "dagster"
        url: "postgresql://{{{{ .username | urlquery }}}}:{{{{ .password | urlquery }}}}@{rds_address}:5432/dagster"
  data:
    - secretKey: username
      remoteRef:
        key: {rds_secret_arn}
        property: username
    - secretKey: password
      remoteRef:
        key: {rds_secret_arn}
        property: password
""",
    )

    write_file(
        "gitops/external-secrets/grafana-cloud-external-secret.yaml",
        f"""apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: sight-poc-grafana-cloud
  namespace: monitoring
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: sight-poc-aws-secretsmanager
  target:
    name: sight-poc-grafana-cloud
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        GRAFANA_CLOUD_LOKI_URL: "{{{{ .logsUrl }}}}"
        GRAFANA_CLOUD_LOKI_USERNAME: "{{{{ .logsUsername }}}}"
        GRAFANA_CLOUD_LOKI_PASSWORD: "{{{{ .logsPassword }}}}"
        GRAFANA_CLOUD_METRICS_URL: "{{{{ .metricsUrl }}}}"
        GRAFANA_CLOUD_METRICS_USERNAME: "{{{{ .metricsUsername }}}}"
        GRAFANA_CLOUD_METRICS_PASSWORD: "{{{{ .metricsPassword }}}}"
  data:
    - secretKey: logsUrl
      remoteRef:
        key: {GRAFANA_CLOUD_SECRET_ARN}
        property: logsUrl
    - secretKey: logsUsername
      remoteRef:
        key: {GRAFANA_CLOUD_SECRET_ARN}
        property: logsUsername
    - secretKey: logsPassword
      remoteRef:
        key: {GRAFANA_CLOUD_SECRET_ARN}
        property: logsPassword
    - secretKey: metricsUrl
      remoteRef:
        key: {GRAFANA_CLOUD_SECRET_ARN}
        property: metricsUrl
    - secretKey: metricsUsername
      remoteRef:
        key: {GRAFANA_CLOUD_SECRET_ARN}
        property: metricsUsername
    - secretKey: metricsPassword
      remoteRef:
        key: {GRAFANA_CLOUD_SECRET_ARN}
        property: metricsPassword
""",
    )

    write_file(
        "gitops/argocd/values/alloy-values.yaml",
        f"""controller:
  type: deployment
  replicas: 1
  podAnnotations:
    k8s.grafana.com/logs.job: sight-poc-alloy
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

alloy:
  envFrom:
    - secretRef:
        name: sight-poc-grafana-cloud
  mounts:
    varlog: true
    dockercontainers: true
  configMap:
    create: true
    content: |
      discovery.kubernetes "pods" {{
        role = "pod"
      }}

      discovery.relabel "pods" {{
        targets = discovery.kubernetes.pods.targets

        rule {{
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }}

        rule {{
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }}

        rule {{
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }}

        rule {{
          source_labels = ["__meta_kubernetes_pod_node_name"]
          target_label  = "node"
        }}

        rule {{
          source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_instance"]
          target_label  = "app_instance"
        }}

        rule {{
          source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_component"]
          target_label  = "app_component"
        }}
      }}

      loki.source.kubernetes "pods" {{
        targets    = discovery.relabel.pods.output
        forward_to = [loki.process.pods.receiver]
      }}

      loki.process "pods" {{
        stage.static_labels {{
          values = {{
            cluster = "{cluster_name}",
            source  = "kubernetes_pod",
          }}
        }}

        forward_to = [loki.write.grafana_cloud.receiver]
      }}

      loki.source.kubernetes_events "cluster" {{
        job_name   = "integrations/kubernetes/eventhandler"
        log_format = "logfmt"
        forward_to = [loki.process.events.receiver]
      }}

      loki.process "events" {{
        stage.static_labels {{
          values = {{
            cluster = "{cluster_name}",
            source  = "kubernetes_event",
          }}
        }}

        forward_to = [loki.write.grafana_cloud.receiver]
      }}

      loki.write "grafana_cloud" {{
        endpoint {{
          url = sys.env("GRAFANA_CLOUD_LOKI_URL")

          basic_auth {{
            username = sys.env("GRAFANA_CLOUD_LOKI_USERNAME")
            password = sys.env("GRAFANA_CLOUD_LOKI_PASSWORD")
          }}
        }}

        external_labels = {{
          cluster = "{cluster_name}",
        }}
      }}

      prometheus.exporter.self "alloy" {{}}

      prometheus.scrape "alloy" {{
        targets    = prometheus.exporter.self.alloy.targets
        forward_to = [prometheus.remote_write.grafana_cloud.receiver]
      }}

      prometheus.remote_write "grafana_cloud" {{
        endpoint {{
          url = sys.env("GRAFANA_CLOUD_METRICS_URL")

          basic_auth {{
            username = sys.env("GRAFANA_CLOUD_METRICS_USERNAME")
            password = sys.env("GRAFANA_CLOUD_METRICS_PASSWORD")
          }}
        }}

        external_labels = {{
          cluster = "{cluster_name}",
        }}
      }}
""",
    )

    write_file(
        "helm/dagster/values-gitops.yaml",
        f"""serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: {dagster_role_arn}

image:
  repository: docker.io/gbieor/sight-poc-data
  tag: v0.2.4

postgresqlSecretName: sight-poc-dagster-db

postgresql:
  host: {rds_address}
  port: 5432
  db: dagster

dataLake:
  bucket: {data_lake_bucket}
  prefix: sight-poc
""",
    )


if __name__ == "__main__":
    main()
