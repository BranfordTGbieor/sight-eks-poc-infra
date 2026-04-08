#!/usr/bin/env bash

set -euo pipefail

TIMEOUT_SECONDS="${WAIT_FOR_APPS_TIMEOUT_SECONDS:-600}"
POLL_SECONDS="${WAIT_FOR_APPS_POLL_SECONDS:-10}"
START_TIME="$(date +%s)"

apps=(
  "hydrosat-root:Healthy:Synced"
  "hydrosat-dagster:Healthy:Synced"
  "hydrosat-alloy:Healthy:Synced"
)

while true; do
  all_ready="true"

  for app_spec in "${apps[@]}"; do
    IFS=":" read -r app expected_health expected_sync <<< "${app_spec}"
    health="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    sync="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"

    printf '%s health=%s sync=%s\n' "${app}" "${health:-<none>}" "${sync:-<none>}"

    if [[ "${health}" != "${expected_health}" || "${sync}" != "${expected_sync}" ]]; then
      all_ready="false"
    fi
  done

  if [[ "${all_ready}" == "true" ]]; then
    echo "Applications reached expected health and sync."
    exit 0
  fi

  if (( "$(date +%s)" - START_TIME >= TIMEOUT_SECONDS )); then
    echo "Timed out waiting for Argo CD applications to settle." >&2
    exit 1
  fi

  sleep "${POLL_SECONDS}"
done
