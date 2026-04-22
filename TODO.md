# Sight PoC Infra TODO

Purpose: local tracker for infrastructure follow-up work. Do not commit unless explicitly requested.

## Now

- [x] Convert hiring feedback into concrete repo hygiene fixes before reusing this project as portfolio material
- [x] Audit `sight-poc-data` runtime/tooling consistency:
  Python version in `pyproject.toml`, Dockerfile base image, CI, and docs must match
- [x] Update the data Dockerfile to use `uv` consistently instead of plain `pip install`
- [x] Add `ruff` formatting and linting to `sight-poc-data`
- [x] Remove hardcoded AWS account IDs from GitOps values/config and resolve them from Terraform outputs, workflow env, or generated values
- [x] Replace Perl-based YAML mutation in `sync-live-config.sh` with a safer structured approach such as `yq`, Helm values generation, or a typed script
- [x] Add an AI assistance disclosure section to committed docs if this project is shared or submitted again

## Next

- [ ] Update GitHub Actions runtime versions and action versions:
  avoid stale Node.js/action runtime warnings
- [x] Complete the repo-wide rebrand to `Sight PoC` across technical identifiers and repo content
- [ ] Plan the Dagster-to-Airflow migration as a separate implementation slice with clear parity requirements
- [ ] Adopt conventional commits consistently across infra and data repos
- [ ] Review dependency freshness:
  Dagster lower bound, Python base image, Terraform providers, GitHub Actions, Helm chart dependencies
- [ ] Review EKS Kubernetes version lifecycle and move away from versions near end of support
- [ ] Add a lightweight "submission hygiene checklist" to the local workflow before future technical challenge submissions
- [ ] Decide whether to add Dagster-specific metrics scraping next, if the workloads expose a stable endpoint worth scraping
- [ ] Decide whether to keep the separate `Grafana Alerting Delivery` workflow as the long-term model or fold it into a broader release workflow later
- [ ] Decide whether the local `terraform/backend.hcl` convention should be aligned with `dev/platform.tfstate` to avoid future local mis-targeting during manual runs

## Later

- [ ] Decide whether Karpenter or Cluster Autoscaler is worth adding for a production-leaning version of the platform
- [ ] Document why autoscaling was intentionally deferred in the demo profile if it remains out of scope
- [ ] Consider upgrading the default Python runtime from 3.11 to a newer supported version if compatible with Dagster and dependencies
- [ ] Consider updating the Dagster dependency floor from the old `1.7` lower bound to a current tested range
- [ ] Validate the `Terraform Delivery` workflow end to end with GitHub Environments and reviewer approval
- [x] Document the final branch-to-environment strategy in the README
- [ ] Decide whether future image promotions should remain direct-to-main or move to PR-based change control
- [ ] Decide later whether an OTEL-native path is even worth the added complexity for this infra-focused repo
- [ ] Revisit shared ingress for Dagster + Argo CD only if external-access polish, TLS, or multiple public UIs become a stronger requirement than the current demo path
- [ ] Decide whether Grafana provider credentials should stay in GitHub Environment secrets or later be resolved from AWS Secrets Manager for workflow parity

## Done Recently

- [x] Replace the heavy in-cluster monitoring footprint with a Grafana Cloud-backed demo path
- [x] Decide the first implementation slice:
  start with Alloy shipping to Grafana Cloud and keep the first metrics slice intentionally light
- [x] Store Grafana Cloud credentials/endpoints in AWS Secrets Manager
- [x] Add External Secrets manifests for Grafana Cloud credentials
- [x] Rework Alloy config to ship to Grafana Cloud instead of local Loki
- [x] Verify Alloy can authenticate and push successfully from the cluster
- [x] Document that the current metrics support is intentionally light
- [x] Expand the first Grafana Cloud coverage beyond Alloy self-metrics by adding Kubernetes events
- [x] Reduce the small-cluster footprint by lowering Dagster requests and switching Alloy to a single lightweight deployment
- [x] Decide that Grafana Cloud-managed alerting is the simpler default than restoring in-cluster Alertmanager
- [x] Decide whether to keep a minimal in-cluster Prometheus/Alertmanager footprint or remove it entirely
- [x] Reduce or remove local Loki / kube-prometheus-stack components for the demo profile
- [x] Add a documented demo-vs-self-hosted observability mode switch in repo values/docs
- [x] Update README and runbook with Grafana Cloud setup, validation steps, and cost justification
- [x] Remove Dagster migration hook dependency on the runtime service account
- [x] Remove Dagster migration hook dependency on the main Dagster ConfigMap
- [x] Encode database credentials safely in the generated PostgreSQL URL secret
- [x] Wire infra image values to the published Docker Hub repository from `sight-poc-data`
- [x] Add an infra-side promotion workflow that updates the Dagster image tag safely
- [x] Decide whether image tag updates happen by PR automation or direct commit bot flow
- [x] Add GitHub Environment protection rules and document them in the repo
- [x] Replace remaining placeholder values for a live demo environment
- [x] Re-run end-to-end validation once Docker Hub release wiring is in place
- [x] Finish infra runbook validation through a fully green Dagster rollout on the smaller Grafana Cloud profile
- [x] Validate that Kubernetes event logs, Dagster workload logs, and Alloy self-metrics appear in Grafana Cloud
- [x] Capture the core end-to-end demo proof:
  one successful Dagster run, one controlled failure, and observability evidence in Grafana Cloud
- [x] Add a repo-native post-apply smoke-check script and wire it into the runbook
- [x] Define and document the first Grafana Cloud alert set:
  start with Dagster `RUN_FAILURE`, then layer in Alloy export/auth issues and missing workload logs
- [x] Complete the final README audit against the assignment checklist and add an explicit coverage matrix
- [x] Update the local TODO to reflect the current post-validation state before the next feature slice
- [x] Scaffold a separate Terraform root for Grafana Cloud alerting so the first alert pack can be managed as code
- [x] Decide to keep Dagster on `LoadBalancer` for the exercise and defer shared ingress until a production-leaning access model is worth the added complexity
- [x] Split repo docs by concern:
  keep repo usage in `README.md`, procedures in `runbook.md`, and rationale/trade-offs in `design-notes.md`
- [x] Decide that Argo CD bootstrap should become a gated post-apply step rather than stay manual-once
- [x] Implement the gated post-apply Argo CD bootstrap and smoke-check stage in `Terraform Delivery`
- [x] Add a post-bootstrap workflow summary step that prints the Dagster public hostname
- [x] Add a dedicated GitHub Actions workflow for the separate Grafana alerting Terraform root
- [x] Switch the first Grafana alert contact point from email to Slack webhook delivery
- [x] Validate the Terraform-managed Grafana alert rule end to end through Slack delivery
- [x] Prove that the environment can be torn down cleanly after removing residual ELB-owned AWS networking resources
