# Sight PoC Infrastructure

Infrastructure and GitOps repository for the Sight PoC platform on AWS.

This repo owns:

- AWS infrastructure with Terraform
- Kubernetes packaging with Helm
- GitOps state with Argo CD
- External Secrets and observability configuration
- infrastructure CI, validation, and delivery workflows

The paired application repo is [sight-poc-data](https://github.com/BranfordTGbieor/sight-poc-data). It builds the application image; this repo consumes and deploys it.

## At a Glance

| Layer | Choice |
| --- | --- |
| Infrastructure | Terraform |
| Kubernetes delivery | Argo CD |
| Runtime packaging | Helm |
| Secrets | AWS Secrets Manager + External Secrets |
| Observability | Grafana Cloud + Alloy |
| CI/CD | GitHub Actions |

## Repository Layout

| Path | Purpose |
| --- | --- |
| `terraform/` | Main AWS platform stack |
| `terraform/modules/` | Reusable Terraform modules |
| `grafana/` | Separate Terraform root for Grafana alerting |
| `helm/dagster/` | Dagster Helm chart |
| `gitops/argocd/` | Argo CD bootstrap and application manifests |
| `gitops/external-secrets/` | External Secret resources |
| `.github/workflows/ci.yml` | Infra validation |
| `.github/workflows/terraform-delivery.yml` | Manual Terraform delivery |
| `.github/workflows/grafana-alerting-delivery.yml` | Manual Grafana alerting delivery |

## Architecture

<img src="utils/images/aws-infra.png" alt="AWS infrastructure diagram" width="1100" />

Source: [utils/mermaid/aws-infra.mmd](./utils/mermaid/aws-infra.mmd)

Key choices:

- Terraform provisions AWS network, EKS, platform, and RDS layers
- Argo CD reconciles cluster state from Git
- Helm packages the Dagster runtime shape
- metadata stays in RDS rather than in-cluster Postgres
- observability defaults to Grafana Cloud plus Alloy to keep demo cost lower

For deeper rationale and trade-offs, see [design-notes.md](./design-notes.md).

## Quick Start

Prerequisites:

- AWS CLI
- Terraform
- kubectl
- Helm
- Docker
- jq

Prepare local Terraform inputs:

```bash
cd terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Example backend config:

```hcl
bucket         = "sight-poc-<unique-suffix>-tf-state"
dynamodb_table = "sight-poc-terraform-locks"
region         = "us-east-1"
key            = "dev/platform.tfstate"
encrypt        = true
```

Provision the main platform:

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Refresh cluster access:

```bash
aws eks update-kubeconfig \
  --region "$(terraform output -raw aws_region)" \
  --name "$(terraform output -raw cluster_name)"
```

## Dagster Image and Secrets

Application images are published from `sight-poc-data`. This repo consumes an explicit image repository and tag through Helm and GitOps.

Bring-up depends on:

1. the RDS master secret created by Terraform
2. a Grafana Cloud logs secret in AWS Secrets Manager
3. a Grafana service account token if you want alert-as-code from `grafana/`

Example Grafana Cloud secret payload:

```json
{
  "logsUrl": "https://logs-prod-<stack>.grafana.net/loki/api/v1/push",
  "logsUsername": "<stack-user-or-tenant-id>",
  "logsPassword": "<grafana-cloud-access-policy-token>",
  "metricsUrl": "https://prometheus-prod-<stack>.grafana.net/api/prom/push",
  "metricsUsername": "<stack-user-or-tenant-id>",
  "metricsPassword": "<grafana-cloud-access-policy-token>"
}
```

Sync live values after apply:

```bash
GRAFANA_CLOUD_SECRET_ARN=arn:aws:secretsmanager:... \
./scripts/sync-live-config.sh
```

For the full operator sequence, use [runbook.md](./runbook.md).

## Validation

Helm:

```bash
helm lint helm/dagster
helm template sight-poc-dagster helm/dagster
```

Terraform:

```bash
terraform init -backend=false
terraform validate
```

Smoke check:

```bash
./scripts/smoke-check.sh
```

Grafana alerting root:

```bash
cd grafana
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

## CI and Delivery

<img src="utils/images/delivery.png" alt="CI and delivery diagram" width="1100" />

Source: [utils/mermaid/delivery.mmd](./utils/mermaid/delivery.mmd)

CI behavior:

- branch CI validates only the surfaces that changed
- Terraform plan runs only for `terraform/**` changes
- Grafana validation runs only for `grafana/**` changes
- Helm render/lint runs only for `helm/**` and `gitops/**` changes
- expensive runs are cancelled when a newer commit supersedes them

Delivery workflows are manual by design:

- `terraform-delivery.yml` applies the main platform stack
- `grafana-alerting-delivery.yml` applies the separate Grafana root

Branch mapping for this PoC:

- `main` or `master` -> `dev`
- `qa` -> `qa`
- `develop` or `dev` -> `dev`

This keeps day-to-day iteration simple while you are the only active contributor. If the repo later needs a stricter promotion model, the mapping can be tightened again.

GitHub Environments:

- `dev` is the default environment for `main`
- `qa` remains available for a separate branch if needed
- `prod` is optional for now, not part of the default branch flow

## Security and Hygiene

- no committed AWS keys or static secrets
- GitHub Actions uses role assumption via OIDC
- live environment values come from Terraform outputs, env vars, or secrets
- YAML mutation uses repo-owned Python scripts instead of brittle text replacement
- `.editorconfig`, `.gitignore`, and `pre-commit` are included for baseline repo hygiene

## AI Assistance Disclosure

This repository was authored and manually reviewed by Branford T. Gbieor with AI assistance used for drafting, refactoring, and documentation support. Final implementation choices and committed changes were reviewed by the author.
