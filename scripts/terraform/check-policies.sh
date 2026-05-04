#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "${repo_root}"

fail() {
  echo "Policy check failed: $1" >&2
  exit 1
}

for env in dev test prod; do
  tfvars_example="terraform/environments/${env}.tfvars.example"
  backend_example="terraform/environments/${env}.platform.backend.hcl.example"

  [ -f "${tfvars_example}" ] || fail "Missing ${tfvars_example}"
  [ -f "${backend_example}" ] || fail "Missing ${backend_example}"

  grep -Eq "^environment[[:space:]]*=[[:space:]]*\"${env}\"$" "${tfvars_example}" || \
    fail "${tfvars_example} must declare environment = \"${env}\""

  grep -Eq "^key[[:space:]]*=[[:space:]]*\"${env}/platform\.tfstate\"$" "${backend_example}" || \
    fail "${backend_example} must use key = \"${env}/platform.tfstate\""
done

for workflow in \
  .github/workflows/ci.yml \
  .github/workflows/terraform-delivery.yml \
  .github/workflows/grafana-alerting-delivery.yml; do
  grep -Fq './scripts/terraform/resolve-environment.sh' "${workflow}" || \
    fail "${workflow} must use scripts/terraform/resolve-environment.sh for environment mapping"
done

tracked_files="$(git ls-files terraform gitops helm/dagster/values-gitops.yaml scripts | grep -Ev '\.example$' || true)"
if [ -n "${tracked_files}" ] && grep -En '\b[0-9]{12}\b' ${tracked_files} 2>/dev/null; then
  fail "Committed config still contains a hardcoded 12-digit account ID"
fi
