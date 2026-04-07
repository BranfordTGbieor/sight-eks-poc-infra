#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"

INFRA_REPO_URL="${INFRA_REPO_URL:-https://github.com/BranfordTGbieor/hydrosat-infra.git}"
GRAFANA_CLOUD_SECRET_ARN="${GRAFANA_CLOUD_SECRET_ARN:?Set GRAFANA_CLOUD_SECRET_ARN to the AWS Secrets Manager ARN for Grafana Cloud observability credentials.}"

tf_output() {
  terraform -chdir="${TF_DIR}" output -raw "$1"
}

AWS_REGION="$(tf_output aws_region)"
CLUSTER_NAME="$(tf_output cluster_name)"
DAGSTER_ROLE_ARN="$(tf_output dagster_service_account_role_arn)"
EXTERNAL_SECRETS_ROLE_ARN="$(tf_output external_secrets_service_account_role_arn)"
DATA_LAKE_BUCKET="$(tf_output data_lake_bucket_name)"
RDS_ADDRESS="$(tf_output rds_address)"
RDS_SECRET_ARN="$(tf_output rds_master_secret_arn)"

replace_all() {
  local old="$1"
  local new="$2"
  shift 2
  perl -0pi -e "s#\Q${old}\E#${new}#g" "$@"
}

perl -0pi -e 's#repoURL: .*#repoURL: '"${INFRA_REPO_URL}"'#g' \
  "${ROOT_DIR}/gitops/argocd/bootstrap/root-application.yaml" \
  "${ROOT_DIR}/gitops/argocd/apps/hydrosat-dagster.yaml" \
  "${ROOT_DIR}/gitops/argocd/apps/external-secrets-resources.yaml"

perl -0pi -e 's#- (?:REPLACE_WITH_GIT_REPOSITORY_URL|git@github\.com:BranfordTGbieor/hydrosat-infra\.git|https://github\.com/BranfordTGbieor/hydrosat-infra\.git)#- '"${INFRA_REPO_URL}"'#g' \
  "${ROOT_DIR}/gitops/argocd/apps/project.yaml" \
  "${ROOT_DIR}/gitops/argocd/apps/external-secrets-operator.yaml" \
  "${ROOT_DIR}/gitops/argocd/apps/monitoring-alloy.yaml"

perl -0pi -e "s#eks\\.amazonaws\\.com/role-arn: .*#eks.amazonaws.com/role-arn: ${EXTERNAL_SECRETS_ROLE_ARN}#g" \
  "${ROOT_DIR}/gitops/argocd/values/external-secrets-values.yaml"

perl -0pi -e "s#region: .*#region: ${AWS_REGION}#g" \
  "${ROOT_DIR}/gitops/external-secrets/cluster-secret-store.yaml"

perl -0pi -e "s#key: (?:REPLACE_WITH_RDS_MASTER_SECRET_ARN|arn:aws:secretsmanager:[^\\n]+rds![^\\n]+)#key: ${RDS_SECRET_ARN}#g" \
  "${ROOT_DIR}/gitops/external-secrets/dagster-db-external-secret.yaml"

perl -0pi -e "s#host: \".*\"#host: \"${RDS_ADDRESS}\"#g; s#url: \".*?\"#url: \"postgresql://{{ .username | urlquery }}:{{ .password | urlquery }}\@${RDS_ADDRESS}:5432/dagster\"#g" \
  "${ROOT_DIR}/gitops/external-secrets/dagster-db-external-secret.yaml"

perl -0pi -e "s#key: (?:REPLACE_WITH_GRAFANA_CLOUD_SECRET_ARN|arn:aws:secretsmanager:[^\\n]+hydrosat/dev/grafana-cloud[^\\n]*)#key: ${GRAFANA_CLOUD_SECRET_ARN}#g" \
  "${ROOT_DIR}/gitops/external-secrets/grafana-cloud-external-secret.yaml"

perl -0pi -e "s#cluster = \"(?:REPLACE_WITH_CLUSTER_NAME|[^\"]+)\"#cluster = \"${CLUSTER_NAME}\"#g" \
  "${ROOT_DIR}/gitops/argocd/values/alloy-values.yaml"

perl -0pi -e "s#eks\\.amazonaws\\.com/role-arn: .*#eks.amazonaws.com/role-arn: ${DAGSTER_ROLE_ARN}#g; s#bucket: .*#bucket: ${DATA_LAKE_BUCKET}#g; s#host: .*#host: ${RDS_ADDRESS}#g" \
  "${ROOT_DIR}/helm/dagster/values-gitops.yaml"

echo "Updated live GitOps config from Terraform outputs."
echo "Review the diff, then commit before bootstrapping Argo CD."
