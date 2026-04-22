# Argo CD Applications

Argo CD is the primary steady-state deployment path for this repository.

Bootstrap model:

1. Install Argo CD in the same EKS cluster for demo simplicity.
2. Make sure the Grafana Cloud AWS Secrets Manager secret exists.
3. Run `./scripts/sync-live-config.sh` from the repo root with:
   - `GRAFANA_CLOUD_SECRET_ARN`
4. Review and commit the generated changes.
5. Apply `gitops/argocd/bootstrap/root-application.yaml`.

What the root application manages:

- `gitops/argocd/apps/project.yaml`
- `gitops/argocd/apps/external-secrets-operator.yaml`
- `gitops/argocd/apps/external-secrets-resources.yaml`
- `gitops/argocd/apps/sight-poc-dagster.yaml`
- `gitops/argocd/apps/monitoring-alloy.yaml`

Sync ordering:

- wave `-1`: Argo CD project
- wave `0`: External Secrets Operator
- wave `1`: ExternalSecret and ClusterSecretStore resources
- wave `2`: Dagster application
- wave `3`: Alloy

Design note:

- same-cluster Argo CD is intentional for this take-home to reduce bootstrap overhead
- a separate management cluster is the better long-term pattern for larger estates
