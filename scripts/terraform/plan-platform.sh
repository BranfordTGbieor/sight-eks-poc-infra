#!/usr/bin/env bash
set -euo pipefail

# Plan the platform Terraform root using the selected environment backend and tfvars files.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/terraform/common.sh
source "${script_dir}/common.sh"

env_ref="${1:-}"
if [ -n "${env_ref}" ]; then
  shift
fi

eval "$("${script_dir}/resolve-environment.sh" "${env_ref}")"
backend_file="${repo_root}/${PLATFORM_BACKEND_FILE}"
tfvars_file="${repo_root}/${PLATFORM_TFVARS_FILE}"

require_file "${backend_file}" "Copy ${backend_file}.example to ${backend_file} and set the real backend values first."
require_file "${tfvars_file}" "Copy ${tfvars_file}.example to ${tfvars_file} and set the real environment values first."

terraform -chdir="${terraform_root}" init -backend-config="${backend_file}"
terraform -chdir="${terraform_root}" plan -var-file="${tfvars_file}" "$@"
