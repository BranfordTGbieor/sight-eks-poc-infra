# Hydrosat Infra Bring-Up Runbook

Use this runbook after `terraform apply` when you want to get the platform up again quickly.

This is intentionally shorter than the earlier validation-heavy version. It focuses on the repeatable path that actually matters:

1. sync live values into GitOps
2. bootstrap Argo CD
3. verify External Secrets
4. verify Dagster
5. verify Alloy log shipping to Grafana Cloud
6. use the recovery steps only if a known failure reappears

This runbook assumes:

- repo root is `hydrosat-infra/`
- Terraform apply has completed successfully
- AWS CLI, `kubectl`, `terraform`, and `git` work locally
- the `hydrosat-data` image tag already exists

## 1. Required Inputs

You need these values before starting:

- Terraform outputs:
  - `aws_region`
  - `cluster_name`
  - `data_lake_bucket_name`
  - `dagster_service_account_role_arn`
  - `external_secrets_service_account_role_arn`
  - `rds_address`
  - `rds_master_secret_arn`
- AWS Secrets Manager secrets:
  - Grafana Cloud observability secret ARN

Recommended commands:

```bash
terraform -chdir=terraform output

aws secretsmanager describe-secret \
  --region us-east-1 \
  --secret-id hydrosat/dev/grafana-cloud \
  --query ARN \
  --output text
```

## 2. Sync Live GitOps Values

Populate the GitOps manifests with the current environment values:

```bash
export GRAFANA_CLOUD_SECRET_ARN=arn:aws:secretsmanager:...
./scripts/sync-live-config.sh
git diff
```

Expected result:

- current Terraform outputs are written into the GitOps manifests
- current Grafana Cloud secret ARN is written into the ExternalSecret resource
- no live runtime placeholders remain in the bootstrap files

Commit and push the sync if it changed tracked files:

```bash
git add gitops helm/dagster/values-gitops.yaml scripts/sync-live-config.sh
git commit -m "Sync live GitOps environment values"
git push
```

## 3. Refresh Cluster Access

```bash
aws eks update-kubeconfig --region us-east-1 --name hydrosat-dev-eks
kubectl config current-context
kubectl get nodes -o wide
kubectl get ns
```

Expected result:

- the EKS context is current
- worker nodes are `Ready`

If `kubectl` points at an old destroyed cluster endpoint, rerun `aws eks update-kubeconfig`.

## 4. Bootstrap Argo CD

Run from the `hydrosat-infra/` repo root:

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-repo-server -n argocd --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-applicationset-controller -n argocd --timeout=300s
kubectl apply -f gitops/argocd/bootstrap/root-application.yaml
kubectl get pods -n argocd
kubectl get applications -n argocd
```

Expected result:

- Argo CD pods are `Running`
- `hydrosat-root` appears in `argocd`

## 5. Baseline App Checks

```bash
kubectl get applications -n argocd
kubectl get externalsecret -A
kubectl get secretstore,clustersecretstore -A
kubectl get pods -A
```

Expected steady-state target:

- `hydrosat-root` is `Synced` and `Healthy`
- External Secrets resources are `Ready`
- Dagster pods are running in `dagster`
- Alloy is running in `monitoring`

## 6. External Secrets Checks

```bash
kubectl get externalsecret -A
kubectl get secret hydrosat-dagster-db -n dagster
kubectl get secret hydrosat-grafana-cloud -n monitoring
```

Expected result:

- `hydrosat-dagster-db` is synced
- `hydrosat-grafana-cloud` is synced

If not:

```bash
kubectl describe externalsecret hydrosat-dagster-db -n dagster
kubectl describe externalsecret hydrosat-grafana-cloud -n monitoring
```

Known failure patterns:

- `AccessDeniedException`
  - External Secrets IRSA policy does not include the current secret ARN
- `SecretSyncedError`
  - stale ARN or wrong secret shape

## 7. Dagster Checks

```bash
kubectl get jobs,pods,svc -n dagster
kubectl logs deployment/hydrosat-dagster-webserver -n dagster --tail=100
kubectl logs deployment/hydrosat-dagster-daemon -n dagster --tail=100
```

Expected result:

- migration job completes
- webserver, daemon, and user-code are `Running`

If Dagster stays `OutOfSync / Missing` in Argo CD:

```bash
kubectl describe application hydrosat-dagster -n argocd
```

Known recovery step for a stuck old migration hook:

```bash
kubectl patch job hydrosat-dagster-migrate -n dagster --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl annotate application hydrosat-dagster -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## 8. Grafana Cloud Observability Checks

```bash
kubectl get applications -n argocd
kubectl get pods -n monitoring
kubectl get secret hydrosat-grafana-cloud -n monitoring
```

Expected result:

- Alloy is running
- the Grafana Cloud credentials secret exists in `monitoring`
- Alloy is exporting its own metrics over Prometheus remote write

Useful spot checks:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/instance=hydrosat-alloy --all-containers --tail=200
kubectl get pods -n dagster
```

## 9. Known Recovery Steps

Use these only if the normal bring-up path gets stuck.

### 9.1 Old kubeconfig endpoint

Symptom:

- `kubectl` points to a destroyed EKS endpoint

Fix:

```bash
aws eks update-kubeconfig --region us-east-1 --name hydrosat-dev-eks
```

### 9.2 Argo CD CRD annotation size error

Symptom:

- Argo CD install fails with CRD annotation or apply-size conflicts

Fix:

```bash
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 9.3 External Secrets permission failure

Symptom:

- `AccessDeniedException` on the Grafana Cloud secret

Fix:

- confirm Terraform includes the current secret ARNs
- rerun `terraform apply`
- refresh the Argo CD apps

### 9.4 Missing EBS storage provisioning

Symptom:

- PVCs stay `Pending`
- event mentions `ebs.csi.aws.com`

Fix:

- ensure the Terraform-managed EBS CSI add-on is applied

Verification:

```bash
kubectl get csidrivers
kubectl get pods -n kube-system | rg ebs-csi
```

### 9.5 Pod capacity pressure

Symptom:

- scheduler says `Too many pods`
- or `Insufficient memory`

Fix:

- temporarily scale the node group up for validation
- after validation, scale it back down to control cost

## 10. Recommended Validation End State

The environment is in a good state when all of these are true:

- `kubectl get applications -n argocd` shows the platform apps healthy enough for demo use
- `kubectl get externalsecret -A` shows all required secrets synced
- `kubectl get pods -n dagster` shows Dagster workloads running
- `kubectl get pods -n monitoring` shows Alloy running
- Dagster is reachable by port-forward

## 11. Scale Down or Destroy After Validation

If you only need a short validation window:

- scale the node group back down in local `terraform.tfvars`
- or destroy the stack entirely

Commands:

```bash
terraform -chdir=terraform apply
terraform -chdir=terraform destroy
```

Use destroy when you are done and want to eliminate AWS cost completely.
