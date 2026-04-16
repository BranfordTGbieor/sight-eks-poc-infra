#!/usr/bin/env bash

set -euo pipefail

failures=0
WAIT_TIMEOUT="${SMOKE_WAIT_TIMEOUT_SECONDS:-10s}"
ROLLOUT_WAIT_TIMEOUT="${SMOKE_ROLLOUT_WAIT_TIMEOUT:-300s}"
RESOURCE_WAIT_TIMEOUT_SECONDS="${SMOKE_RESOURCE_WAIT_TIMEOUT_SECONDS:-300}"
RESOURCE_WAIT_POLL_SECONDS="${SMOKE_RESOURCE_WAIT_POLL_SECONDS:-10}"

section() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  printf '[PASS] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  failures=$((failures + 1))
}

check() {
  local description="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

wait_for_check() {
  local description="$1"
  shift

  local start_time
  start_time="$(date +%s)"

  while true; do
    if "$@" >/dev/null 2>&1; then
      pass "$description"
      return 0
    fi

    if (( "$(date +%s)" - start_time >= RESOURCE_WAIT_TIMEOUT_SECONDS )); then
      fail "$description"
      return 1
    fi

    sleep "${RESOURCE_WAIT_POLL_SECONDS}"
  done
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$tool" >&2
    exit 1
  fi
}

app_status_check() {
  local app="$1"
  local expected_sync="$2"
  local expected_health="$3"
  local sync health

  sync="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  if [[ "$sync" == "$expected_sync" && "$health" == "$expected_health" ]]; then
    pass "application/$app is $expected_sync / $expected_health"
  else
    fail "application/$app expected $expected_sync / $expected_health but saw ${sync:-<none>} / ${health:-<none>}"
  fi
}

app_exists_check() {
  local app="$1"

  if kubectl get application "$app" -n argocd >/dev/null 2>&1; then
    pass "application/$app exists"
  else
    fail "application/$app does not exist"
  fi
}

app_exists_and_healthy_check() {
  local app="$1"
  local sync health

  if ! kubectl get application "$app" -n argocd >/dev/null 2>&1; then
    fail "application/$app does not exist"
    return 1
  fi

  sync="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  if [[ "$health" == "Healthy" && "$sync" == "Synced" ]]; then
    pass "application/$app is Synced / Healthy"
  else
    fail "application/$app expected Synced / Healthy but saw ${sync:-<none>} / ${health:-<none>}"
  fi
}

app_healthy_check() {
  local app="$1"
  local health

  if ! kubectl get application "$app" -n argocd >/dev/null 2>&1; then
    fail "application/$app does not exist"
    return 1
  fi

  health="$(kubectl get application "$app" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || true)"

  if [[ "$health" == "Healthy" ]]; then
    pass "application/$app is Healthy"
  else
    fail "application/$app expected Healthy but saw ${health:-<none>}"
  fi
}

require_tool kubectl

section "Cluster"
check "kubectl can reach the cluster" kubectl cluster-info
check "at least one node is Ready" bash -lc "kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready '"

section "Argo CD"
check "argocd namespace exists" kubectl get namespace argocd
check "argocd-server deployment exists" kubectl get deployment argocd-server -n argocd
check "argocd-server is Available" kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout="${WAIT_TIMEOUT}"
check "argocd-repo-server is Available" kubectl wait --for=condition=Available deployment/argocd-repo-server -n argocd --timeout="${WAIT_TIMEOUT}"
check "argocd-applicationset-controller is Available" kubectl wait --for=condition=Available deployment/argocd-applicationset-controller -n argocd --timeout="${WAIT_TIMEOUT}"
app_status_check hydrosat-root Synced Healthy
app_healthy_check hydrosat-external-secrets-operator
app_healthy_check hydrosat-external-secrets-resources
app_exists_check hydrosat-dagster
app_exists_check hydrosat-alloy

section "External Secrets"
wait_for_check "dagster DB ExternalSecret is Ready" bash -lc "[[ \"\$(kubectl get externalsecret hydrosat-dagster-db -n dagster -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == \"True\" ]]"
wait_for_check "Grafana Cloud ExternalSecret is Ready" bash -lc "[[ \"\$(kubectl get externalsecret hydrosat-grafana-cloud -n monitoring -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == \"True\" ]]"
wait_for_check "dagster DB secret exists" kubectl get secret hydrosat-dagster-db -n dagster
wait_for_check "Grafana Cloud secret exists" kubectl get secret hydrosat-grafana-cloud -n monitoring

section "Dagster"
wait_for_check "dagster webserver deployment exists" kubectl get deployment hydrosat-dagster-webserver -n dagster
wait_for_check "dagster daemon deployment exists" kubectl get deployment hydrosat-dagster-daemon -n dagster
wait_for_check "dagster user-code deployment exists" kubectl get deployment hydrosat-dagster-user-code -n dagster
check "dagster webserver deployment is Available" kubectl rollout status deployment/hydrosat-dagster-webserver -n dagster --timeout="${ROLLOUT_WAIT_TIMEOUT}"
check "dagster daemon deployment is Available" kubectl rollout status deployment/hydrosat-dagster-daemon -n dagster --timeout="${ROLLOUT_WAIT_TIMEOUT}"
check "dagster user-code deployment is Available" kubectl rollout status deployment/hydrosat-dagster-user-code -n dagster --timeout="${ROLLOUT_WAIT_TIMEOUT}"
wait_for_check "dagster webserver service exists" kubectl get service hydrosat-dagster-webserver -n dagster

section "Monitoring"
wait_for_check "Alloy deployment exists" kubectl get deployment hydrosat-alloy -n monitoring
check "Alloy deployment is Available" kubectl wait --for=condition=Available deployment/hydrosat-alloy -n monitoring --timeout="${WAIT_TIMEOUT}"

section "Summary"
if [[ "$failures" -eq 0 ]]; then
  printf 'Smoke check passed.\n'
else
  printf 'Smoke check failed with %d issue(s).\n' "$failures"
  exit 1
fi
