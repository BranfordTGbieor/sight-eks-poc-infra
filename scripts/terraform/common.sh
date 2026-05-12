#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
terraform_root="${repo_root}/terraform"
environment_dir="${terraform_root}/environments"

resolve_environment() {
  local ref="${1:-}"

  if [ -z "${ref}" ]; then
    if [ -n "${TARGET_ENVIRONMENT:-}" ]; then
      ref="${TARGET_ENVIRONMENT}"
    elif git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      ref="$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD)"
    else
      echo "Unable to infer environment. Pass one of: main, test, prod." >&2
      return 1
    fi
  fi

  case "${ref}" in
    main)
      printf 'dev\n'
      ;;
    test)
      printf 'test\n'
      ;;
    prod)
      printf 'prod\n'
      ;;
    *)
      echo "Unsupported environment or branch: ${ref}. Use main, test, or prod." >&2
      return 1
      ;;
  esac
}

require_file() {
  local path="$1"
  local help_message="$2"

  if [ ! -f "${path}" ]; then
    echo "Missing required file: ${path}" >&2
    echo "${help_message}" >&2
    return 1
  fi
}
