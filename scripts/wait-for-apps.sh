#!/usr/bin/env bash

set -euo pipefail

TIMEOUT_SECONDS="${WAIT_FOR_APPS_TIMEOUT_SECONDS:-600}"
POLL_SECONDS="${WAIT_FOR_APPS_POLL_SECONDS:-10}"
START_TIME="$(date +%s)"

root_app="hydrosat-root"
healthy_child_apps=(
  "hydrosat-external-secrets-operator"
  "hydrosat-external-secrets-resources"
)
existing_child_apps=(
  "hydrosat-dagster"
  "hydrosat-alloy"
)

while true; do
  all_ready="true"

  root_health="$(kubectl get application "${root_app}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  root_sync="$(kubectl get application "${root_app}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  printf '%s health=%s sync=%s\n' "${root_app}" "${root_health:-<none>}" "${root_sync:-<none>}"

  if [[ "${root_health}" != "Healthy" || "${root_sync}" != "Synced" ]]; then
    all_ready="false"
  fi

  for app in "${healthy_child_apps[@]}"; do
    if kubectl get application "${app}" -n argocd >/dev/null 2>&1; then
      health="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
      sync="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
      printf '%s health=%s sync=%s\n' "${app}" "${health:-<none>}" "${sync:-<none>}"

      if [[ "${health}" != "Healthy" ]]; then
        all_ready="false"
      fi
    else
      printf '%s health=<none> sync=<none>\n' "${app}"
      all_ready="false"
    fi
  done

  for app in "${existing_child_apps[@]}"; do
    if kubectl get application "${app}" -n argocd >/dev/null 2>&1; then
      health="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
      sync="$(kubectl get application "${app}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
      printf '%s health=%s sync=%s\n' "${app}" "${health:-<none>}" "${sync:-<none>}"
    else
      printf '%s health=<none> sync=<none>\n' "${app}"
      all_ready="false"
    fi
  done

  if [[ "${all_ready}" == "true" ]]; then
    echo "Root application is synced, External Secrets is healthy, and workload applications exist."
    exit 0
  fi

  if (( "$(date +%s)" - START_TIME >= TIMEOUT_SECONDS )); then
    echo "Timed out waiting for Argo CD applications to settle." >&2
    exit 1
  fi

  sleep "${POLL_SECONDS}"
done
