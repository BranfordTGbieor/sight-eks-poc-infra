# Hydrosat Design Notes

This document holds the architectural decisions, trade-offs, operational rationale, and production-leaning considerations for the Hydrosat platform.

Use it alongside:

- `README.md` for repository usage, provisioning, and validation
- `runbook.md` for repeatable bring-up and recovery steps

## Assignment Coverage

| Assignment area | What this repo implements | Current status |
| --- | --- | --- |
| Provision infrastructure with Terraform | VPC, EKS, managed node group, RDS PostgreSQL, S3 lake bucket, IAM, and supporting platform resources | Implemented and validated |
| Deploy Dagster on EKS | Helm-packaged Dagster webserver, daemon, migration job, and gRPC user-code workload | Implemented and validated |
| Use PostgreSQL for Dagster metadata | Amazon RDS PostgreSQL with secrets delivered through External Secrets | Implemented and validated |
| Expose the Dagster UI | Kubernetes `LoadBalancer` service for demo access | Implemented and validated |
| Run a dummy data pipeline | Split-repo flow with `hydrosat-data` image, sample ingestion, and staged/curated outputs in S3 | Implemented and validated |
| Monitor and observe the platform | Alloy shipping pod logs, Dagster workload logs, events, and self-metrics to Grafana Cloud | Implemented and validated |
| Alert on Dagster job failure | Grafana Cloud alerting-as-code with validated Slack delivery on controlled Dagster failure | Implemented and validated |
| Document architecture and usage | README, runbook, design notes, and repo-native smoke check | Implemented |

## Current Validation Status

- cluster bring-up is repeatable through Terraform, GitOps sync, Argo CD bootstrap, and the repo smoke check
- Dagster steady state is healthy on the smaller 3-node cluster profile
- success and controlled failure runs are both proven
- Grafana Cloud ingestion of Dagster workload logs is proven
- Grafana Cloud alerting-as-code is proven end to end through Slack delivery

## Operational Decisions

### Job Failure Alerting

Dagster remains the source of truth for job-failure semantics. The chart still supports an Alertmanager URL, but the default GitOps profile leaves it blank so the platform can come up without the heavier in-cluster alerting stack.

Current recommendation:

- use Grafana Cloud-managed alerting for this repo's default observability path
- manage the first Grafana Cloud alerting resources through the separate `grafana/` Terraform root
- keep in-cluster Alertmanager out of the default profile
- document the chosen rules, contact points, and notification-policy shape in Git

Recommended first alert set:

- Alloy export/auth failures
- Dagster webserver unavailable
- Dagster daemon unavailable
- Dagster `RUN_FAILURE` logs in Grafana Cloud Loki
- absence of expected Dagster workload logs over a recent window

Recommended implementation order:

1. Dagster run failure log alert
2. Dagster webserver unavailable alert
3. Dagster daemon unavailable alert
4. Alloy export/auth failure alert
5. missing Dagster workload log heartbeat alert

Suggested notification model:

- one low-noise contact point for the exercise, such as Slack
- one default notification policy for `severity=warning`
- one dedicated policy for `service=dagster` so job failures do not mix with general platform noise

Decision for this repo:

- use alert-as-code for the small first Grafana Cloud alert pack through the separate `grafana/` Terraform root
- keep the scope intentionally small and avoid a larger alerting platform refactor
- use a Grafana service account token for Terraform provider authentication rather than reusing runtime ingestion credentials

Guardrails:

- keep the current Terraform-managed scope to one contact point, one notification-policy branch, and one Dagster failure rule
- revisit the design only if the alert set becomes large enough to justify modules, multiple policy branches, or environment-specific promotion logic

### Secrets Management

AWS Secrets Manager is the source of truth for:

- Dagster database credentials
- Grafana Cloud logs and metrics credentials
- optional Grafana service account token used by the separate `grafana/` Terraform root

External Secrets Operator syncs runtime values into Kubernetes Secrets. This is materially better than embedding SaaS credentials directly in Helm values or Git.

### Data Lake Storage

The platform provisions an S3-backed data lake bucket for the Dagster sample pipeline with a layered layout:

- `raw/satellite_observations/...`
- `staging/satellite_observations/...`
- `curated/tile_summary/...`

Dagster accesses the bucket through IRSA rather than static AWS credentials. The paired `hydrosat-data` repo uses Python for raw ingestion and dbt-backed DuckDB transforms for staging and curated outputs before publishing them back into S3.

### Secret Rotation Lifecycle

Secret rotation behavior is explicit:

- Dagster DB secret refresh interval: `1h`
- Grafana Cloud secret refresh interval: `15m`

Operational model:

1. Rotate or update the value in AWS Secrets Manager.
2. Wait for External Secrets to reconcile the Kubernetes Secret.
3. Restart Alloy workloads if Grafana Cloud credentials changed.
4. Restart Dagster workloads if the rotated value affects environment-sourced database credentials.
5. Validate application health and observability export.

### Networking and Access

Networking decisions:

- two public and two private subnets across AZs
- EKS worker nodes in private subnets
- single NAT gateway to stay cost-conscious for the exercise
- EKS private endpoint access enabled, with public access still available for easier bootstrap
- Dagster UI exposed through a Kubernetes `LoadBalancer`

The public EKS endpoint can be narrowed through `cluster_endpoint_public_access_cidrs`. For a longer-lived environment, I would typically disable public endpoint access after bootstrap.

External access decision:

- keep the current Dagster `LoadBalancer` plus Argo CD port-forward model for the exercise
- do not introduce a shared ingress controller yet

Why this is the right short-term choice:

- the assignment only requires that the Dagster UI be reachable
- the direct `LoadBalancer` path is already validated end to end
- adding ingress now would also add DNS, TLS, host routing, and another controller to validate
- Argo CD does not need public exposure for the assignment because port-forward already gives an authenticated management path

### Production Access Model

For a production-leaning environment, Dagster should not remain directly open behind a plain public service.

Recommended production shape:

- ingress or ALB-based routing in front of Dagster and, if needed, Argo CD
- ACM public certificate for HTTPS termination
- DNS hostnames such as `dagster.<domain>` and `argocd.<domain>`
- authentication in front of Dagster via OIDC, SSO, or an auth proxy
- Argo CD either kept internal or exposed with stronger access controls than the demo profile

Important note:

- ACM public certificates are free
- TLS alone is not enough; production access should be both encrypted and access-controlled

## Cost Justification and Trade-Offs

### Sizing

Current demo defaults are intentionally modest:

- EKS node group: `t3.small`, `min=3`, `desired=3`, `max=3`
- RDS: PostgreSQL 16 on `db.t4g.micro`, `Multi-AZ = false`
- VPC Flow Logs: enabled with `7d` retention
- RDS Performance Insights: disabled
- RDS Enhanced Monitoring: disabled
- observability data plane: Grafana Cloud-managed, with Alloy shipping logs out of cluster

The goal is to keep the review environment inexpensive without changing the overall platform shape.

### Demo vs Production Defaults

| Area | Demo default in repo | Production-leaning recommendation | Why |
| --- | --- | --- | --- |
| EKS nodes | `t3.small`, `min=3`, `desired=3`, `max=3` | start at `min=2`, `desired=2`, `max=4+` with sizing based on real load | the exercise now uses the validated 3-node baseline because Dagster, Argo CD, and observability share one cluster |
| RDS topology | `db.t4g.micro`, `Multi-AZ = false` | `db.t4g.small` or higher, `Multi-AZ = true` | the demo optimizes cost; production should optimize availability first |
| RDS storage | `20 GiB`, autoscale to `100 GiB` | keep autoscaling, raise floor only if usage justifies it | autoscaling is already the better pattern than fixed overprovisioning |
| VPC Flow Logs | enabled, `7d` retention | `30d+` retention or org-standard log archival | short retention preserves the network-visibility story without paying for a long audit window |
| RDS telemetry | Performance Insights and Enhanced Monitoring disabled | enable both when deeper DB troubleshooting justifies the spend | optional RDS telemetry is easy to restore later, but not necessary for a short-lived demo |
| Observability | Grafana Cloud for logs, no heavy local LGTM stack by default | choose Grafana Cloud or a right-sized self-hosted stack per environment | the demo path optimizes for repeatable bring-up cost and lower cluster pressure |
| Exposure | `LoadBalancer` for Dagster only | ingress controller plus TLS and host-based routing | direct exposure is simpler for review, ingress is cleaner once multiple services need external access |

### Ingress and Exposure Trade-Offs

The current repo exposes Dagster through a Kubernetes `LoadBalancer` service instead of introducing an ingress controller.

Why this is acceptable here:

- it keeps the bootstrap path simple
- it makes the UI easy for a reviewer to access
- it avoids adding another controller, another chart, and another TLS/DNS story before the core platform is complete

Why I would revisit it later:

- an ingress controller becomes more attractive once there are multiple services to expose
- it gives better control over host-based routing, TLS policy, and access controls
- it is the cleaner path if Grafana, Argo CD, and Dagster all need polished external access patterns

Decision:

- for this exercise, keep the current `LoadBalancer` for Dagster and keep Argo CD internal or port-forwarded
- for a production-leaning next step, move Dagster and Argo CD behind a shared ingress controller with TLS and host-based routing

## Challenges Encountered

Notable implementation and validation issues:

- Dagster migration hook ordering problems in Argo CD `PreSync`
- stale DB URL generation and secret sync regressions
- small-cluster scheduling pressure before resource requests were lowered
- destroy-time AWS cleanup delays caused by Kubernetes-created `LoadBalancer` resources
- dbt and DuckDB runtime issues that required several application releases to stabilize the demo path

Why this matters:

- it shows the final design was not only planned but also exercised and corrected under real conditions

## Best Practices Applied

- split infrastructure and application repos to keep ownership boundaries clear
- keep runtime secrets out of Git and out of Helm values
- use IRSA instead of static AWS credentials
- keep the demo footprint cost-conscious without changing the fundamental architecture
- use GitOps for steady-state reconciliation
- keep alerting and access decisions documented in Git and validated through code where practical

## Production Improvements

If this moved beyond an exercise, the first improvements would be:

1. expand and harden the Grafana alert pack beyond the first validated Slack rule
2. move Dagster and optionally Argo CD behind shared ingress with TLS and auth
3. tighten EKS public API exposure after bootstrap
4. raise RDS availability posture with Multi-AZ and revisit instance sizing
5. add stronger post-apply automation and smoke tests
6. decide whether to keep Argo CD bootstrap in the current gated post-apply delivery step or split it into a separate operational workflow

## Delivery Decisions

### Argo CD Bootstrap

Decision:

- Argo CD bootstrap should become a gated post-apply step
- it should not be folded directly into the main AWS Terraform root

Why:

- Terraform should remain responsible for cloud infrastructure lifecycle
- Argo CD bootstrap is an operational handoff into the GitOps control plane, not a pure cloud resource concern
- keeping bootstrap as a gated post-apply step preserves reviewability while avoiding a tighter coupling between AWS infra apply and cluster workload bootstrap

Recommended shape:

1. `Terraform Delivery` completes and passes the environment gate
2. a reviewed post-apply stage runs:
   - sync live GitOps values if needed
   - refresh kubeconfig
   - install or verify Argo CD
   - apply the root application
   - run the repo smoke check
3. operator reviews the resulting app health before moving on to deeper validation

Current implementation status:

- the workflow now includes a gated post-apply bootstrap job
- that path has been validated against a real environment

Why this is better than the current manual-once flow:

- the flow becomes repeatable
- the bootstrap steps remain explicit and reviewable
- the smoke check gives a better handoff point than a loosely documented set of shell commands
- it aligns with the existing GitHub Environment approval model already documented in the repo
