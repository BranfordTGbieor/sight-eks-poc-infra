#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/terraform/common.sh
source "${script_dir}/common.sh"

terraform fmt -check -recursive "${terraform_root}"
terraform -chdir="${terraform_root}" init -backend=false
terraform -chdir="${terraform_root}" validate
