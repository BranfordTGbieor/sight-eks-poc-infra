# Sight PoC Design Notes

This document captures the current infrastructure decisions for the Sight PoC platform. It is intentionally concise; procedural bring-up and recovery steps belong in [runbook.md](./runbook.md), while day-to-day usage belongs in [README.md](./README.md).

## Current Architecture

Sight PoC uses a split-repo model:

- `sight-poc-data` owns application code, orchestration logic, tests, and image publishing.
- `sight-poc-infra` owns AWS infrastructure, Kubernetes packaging, GitOps state, and delivery workflows.

The infrastructure repo provisions the AWS platform with Terraform, deploys workloads through Helm and Argo CD, and uses External Secrets to sync runtime secrets from AWS Secrets Manager. Grafana Cloud plus Alloy is the default observability path to keep the PoC lighter than a full in-cluster monitoring stack.

## Key Decisions

| Decision | Current choice | Rationale |
| --- | --- | --- |
| Infrastructure as code | Terraform | Portable, reviewable, and familiar for AWS platform work |
| Runtime delivery | Argo CD + Helm | Separates infrastructure lifecycle from Kubernetes reconciliation |
| Secrets | AWS Secrets Manager + External Secrets | Keeps credentials out of Git and Helm values |
| Data lake | S3 | Simple durable storage for raw, staged, and curated layers |
| Metadata DB | Amazon RDS PostgreSQL | Avoids running a stateful database inside the cluster |
| Observability | Grafana Cloud + Alloy | Keeps cluster footprint and demo cost lower |
| Branch model | `main -> dev`, `tes -> test`, `prod -> prod` | Reduces solo-maintainer friction while preserving environment mapping |

## Current Trade-Offs

The platform is deliberately PoC-sized. It favors repeatable bring-up, low operating cost, and a clear architecture story over full production hardening.

Known trade-offs:

- Dagster is exposed with a `LoadBalancer` for simple demo access.
- Argo CD is bootstrapped into the same cluster it manages.
- The default node group model is still simple and should be split into platform/workload groups next.
- Grafana Cloud coverage is useful but not yet a complete KPI pack.
- CloudWatch remains the right source for many AWS-native infrastructure metrics, so Grafana Cloud should focus on GitOps, workload, and data-platform health signals.

## Near-Term Design Direction

### EKS Node Groups

Next target: split the current EKS worker model into at least two node groups.

- `platform`: Argo CD, External Secrets, Alloy, and support workloads
- `workload`: Dagster now, Airflow and data workloads later

Why:

- isolates platform control-plane add-ons from data workload pressure
- makes future upgrades and taints/tolerations easier
- improves capacity planning and cost attribution
- gives the Airflow migration a cleaner landing zone

### Observability KPIs

Next target: improve Grafana Cloud coverage without duplicating metrics already well-covered by CloudWatch.

Prioritize:

- Argo CD app sync and health state
- External Secrets sync failures and stale secrets
- orchestration job failure, heartbeat, and runtime readiness
- missing log ingestion for critical workloads
- Alloy export/auth failures

Avoid in the first pass:

- duplicating basic EC2, RDS, EKS, and network metrics already available through CloudWatch
- broad low-signal dashboards that do not directly support demo or recovery workflows
- noisy alerts without a clear owner, severity, and runbook action

### Delivery Model

For now, changes land directly on `main` because this is a solo-maintained PoC. Manual delivery workflows still provide a review point before infrastructure apply.

The model should be revisited if:

- more contributors join
- `test` or `prod` becomes long-lived
- image promotion needs stronger change control
- the project is used beyond portfolio/demo purposes

## Runbook Decision

`runbook.md` should stay. The README should remain compact, while the runbook owns the repeatable operational sequence:

- sync live GitOps values
- bootstrap Argo CD
- run smoke checks
- inspect External Secrets
- validate Dagster and Alloy
- recover from known failure modes

If those operational steps become automated or obsolete, the runbook can be shortened again rather than removed prematurely.

## Production-Leaning Improvements

If this project moves beyond a PoC, prioritize:

1. split EKS node groups for platform and workloads
2. improve Grafana Cloud KPI coverage around GitOps, secrets, orchestration, and log ingestion
3. move external UIs behind ingress, TLS, and authentication
4. tighten EKS public endpoint access after bootstrap
5. raise RDS availability posture with Multi-AZ and right-sized instances
6. decide whether image promotion stays direct-to-main or moves to PR-based promotion
7. align Airflow deployment design with the future data repo migration

## Best-Practice Principles

- keep secrets out of Git
- prefer generated or synced live values over committed environment constants
- avoid duplicating telemetry sources without a clear operational reason
- keep the default profile cost-conscious but structurally realistic
- separate platform workloads from application workloads as the system grows
- keep CI and delivery scoped to the files and environments that actually changed
- document trade-offs explicitly when choosing a simpler PoC path over a production default
