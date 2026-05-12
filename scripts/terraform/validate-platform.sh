#!/usr/bin/env bash
set -euo pipefail

# Run the basic Terraform hygiene checks used before plan or apply.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/terraform/common.sh
source "${script_dir}/common.sh"

terraform fmt -check -recursive "${terraform_root}"
terraform -chdir="${terraform_root}" init -backend=false
terraform -chdir="${terraform_root}" validate
