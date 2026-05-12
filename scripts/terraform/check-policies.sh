#!/usr/bin/env bash
set -euo pipefail

# Render structured repo state for Conftest, then evaluate the Rego policy set.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
policy_input="/tmp/sight-poc-infra-policy-input.json"

python3 "${script_dir}/render_policy_input.py" > "${policy_input}"

cleanup() {
  rm -f "${policy_input}"
}
trap cleanup EXIT

# Prefer a local Conftest binary, but fall back to a pinned container in CI or fresh shells.
if command -v conftest >/dev/null 2>&1; then
  conftest test --policy "${repo_root}/policy" --parser json "${policy_input}"
else
  docker run --rm \
    -v "${repo_root}":/project \
    -v /tmp:/tmp \
    -w /project \
    openpolicyagent/conftest:v0.58.0 \
    test --policy /project/policy --parser json /tmp/$(basename "${policy_input}")
fi
