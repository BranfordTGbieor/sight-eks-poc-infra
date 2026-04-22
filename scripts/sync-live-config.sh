#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${INFRA_REPO_URL:-}" ]]; then
  INFRA_REPO_URL="REPLACE_WITH_GIT_REPOSITORY_URL"
fi

if [[ -z "${GITOPS_TARGET_REVISION:-}" ]]; then
  if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GITOPS_TARGET_REVISION="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)"
  else
    GITOPS_TARGET_REVISION="REPLACE_WITH_GIT_TARGET_REVISION"
  fi
fi

export INFRA_REPO_URL
export GITOPS_TARGET_REVISION

exec python3 "${ROOT_DIR}/scripts/sync_live_config.py"
