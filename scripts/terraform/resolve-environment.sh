#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/terraform/common.sh
source "${script_dir}/common.sh"

target_environment="$(resolve_environment "${1:-}")"

printf 'TARGET_ENVIRONMENT=%s\n' "${target_environment}"
printf 'PLATFORM_BACKEND_KEY=%s/platform.tfstate\n' "${target_environment}"
printf 'GRAFANA_BACKEND_KEY=%s/grafana-alerting.tfstate\n' "${target_environment}"
printf 'PLATFORM_TFVARS_FILE=terraform/environments/%s.tfvars\n' "${target_environment}"
printf 'PLATFORM_BACKEND_FILE=terraform/environments/%s.platform.backend.hcl\n' "${target_environment}"
