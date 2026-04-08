# Hydrosat Infra Bring-Up Runbook

Use this runbook after `terraform apply` when you want to get the platform up again quickly.

This is intentionally shorter than the earlier validation-heavy version. It focuses on the repeatable path that actually matters:

1. sync live values into GitOps
2. bootstrap Argo CD
3. run the repo smoke check
4. verify External Secrets
5. verify Dagster
6. verify Alloy log shipping to Grafana Cloud
7. use the recovery steps only if a known failure reappears

This runbook assumes:

- repo root is `hydrosat-infra/`
- Terraform apply has completed successfully
- AWS CLI, `kubectl`, `terraform`, and `git` work locally
- the `hydrosat-data` image tag already exists and has passed CI before release

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

## 5. Run the Smoke Check

Run the repo smoke check once Argo CD has bootstrapped:

```bash
./scripts/smoke-check.sh
```

Expected result:

- the cluster is reachable
- Argo CD core deployments are available
- `hydrosat-root`, `hydrosat-dagster`, and `hydrosat-alloy` are `Synced / Healthy`
- External Secrets, Dagster, and Alloy baseline resources exist and are ready

If it fails, use the section outputs to decide whether the issue is:

- cluster access
- Argo CD bootstrap
- External Secrets sync
- Dagster rollout
- Alloy rollout

## 6. Baseline App Checks

```bash
kubectl get applications -n argocd
kubectl get externalsecret -A
kubectl get secretstore,clustersecretstore -A
kubectl get pods -A
```

Expected steady-state target:

- `hydrosat-root` is `Synced` and `Healthy`
- External Secrets resources are `Ready`
- Dagster webserver and user-code are running in `dagster`
- Alloy is running in `monitoring`

## 7. External Secrets Checks

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
- `401 Unauthorized`
  - Grafana Cloud token scope is wrong
  - use `logs:write` and `metrics:write`, then restart Alloy after the secret refresh

## 8. Dagster Checks

```bash
kubectl get jobs,pods,svc -n dagster
kubectl logs deployment/hydrosat-dagster-webserver -n dagster --tail=100
kubectl logs deployment/hydrosat-dagster-daemon -n dagster --tail=100
```

Expected result:

- migration job completes
- webserver, daemon, and user-code are `Running`
- the smaller 3-node demo cluster is sufficient with the current lightweight profile

Validated state from the latest bring-up:

- Dagster reached `Synced / Healthy`
- the demo job completed successfully
- a controlled failure run also executed as expected for alert-validation work

If Dagster stays `OutOfSync / Missing` in Argo CD:

```bash
kubectl describe application hydrosat-dagster -n argocd
```

Known recovery step for a stuck old migration hook:

```bash
kubectl patch job hydrosat-dagster-migrate -n dagster --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl annotate application hydrosat-dagster -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

Known Dagster failure patterns:

- the migration job can fail if the DB URL in `hydrosat-dagster-db` is stale
- force a refresh on the ExternalSecret before retrying the Dagster app:

```bash
kubectl annotate externalsecret hydrosat-dagster-db -n dagster force-sync=$(date +%s) --overwrite
```

- on the current small demo cluster, the Dagster daemon can still remain `Pending` due to:
  - `Too many pods`
  - `Insufficient memory`

## 9. Grafana Cloud Observability Checks

```bash
kubectl get applications -n argocd
kubectl get pods -n monitoring
kubectl get secret hydrosat-grafana-cloud -n monitoring
```

Expected result:

- Alloy is running
- the Grafana Cloud credentials secret exists in `monitoring`
- Alloy is exporting its own metrics over Prometheus remote write
- Kubernetes events are also shipped as logs

Useful spot checks:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/instance=hydrosat-alloy --all-containers --tail=200
kubectl get pods -n dagster
```

Coverage expectation after bootstrap:

- pod logs in Grafana Cloud Loki
- Kubernetes events in Grafana Cloud Loki
- Alloy self-metrics in Grafana Cloud Metrics

Useful LogQL checks:

```logql
{cluster="hydrosat-dev-eks", namespace="dagster", source="kubernetes_pod"}
```

```logql
{cluster="hydrosat-dev-eks", namespace="dagster", app_component="user-code", source="kubernetes_pod"} |= "RUN_FAILURE" |= "hydrosat_lakehouse_job"
```

Validated result from the latest run:

- Dagster `webserver`, `daemon`, and `user-code` logs were visible in Grafana Cloud
- Kubernetes events were visible in Grafana Cloud
- the controlled Dagster failure was visible through `RUN_FAILURE` log lines in the `user-code` stream

If you rotate the Grafana Cloud secret value:

```bash
kubectl annotate externalsecret hydrosat-grafana-cloud -n monitoring force-sync=$(date +%s) --overwrite
kubectl rollout restart deployment/hydrosat-alloy -n monitoring
```

## 9.1 Grafana Cloud Alerting

The current recommended alerting path is Grafana Cloud-managed alerting through the separate `grafana/` Terraform root, not in-cluster Alertmanager.

For this repo, the first alert set should be:

- Alloy export/auth failures
- Dagster webserver unavailable
- Dagster daemon unavailable
- repeated Dagster error logs
- no recent Dagster workload logs during expected activity windows

Pragmatic first implementation:

1. populate `grafana/terraform.tfvars` with the Grafana URL, service account token, email addresses, and Loki data source UID
2. apply the separate `grafana/` Terraform root
3. start with a Dagster log alert on `RUN_FAILURE` for `hydrosat_lakehouse_job`
4. document the chosen rules and thresholds in this repo after validation

This keeps the cluster simpler while still giving you a credible alerting story for the demo.

Current Terraform-managed scope:

1. one exercise contact point:
   - email
2. one notification-policy branch:
   - `service=dagster`
3. one required rule:
   - `Dagster Job Failure`

Keep the scope this small until live validation is complete.

Suggested first Dagster alert rule:

- name: `Dagster Job Failure`
- labels:
  - `service=dagster`
  - `severity=warning`
- evaluate every: `1m`
- for: `0m`
- query:

```logql
sum(count_over_time({cluster="hydrosat-dev-eks", namespace="dagster", app_component="user-code", source="kubernetes_pod"} |= "RUN_FAILURE" |= "hydrosat_lakehouse_job" [5m])) > 0
```

Expected validation:

1. apply the `grafana/` Terraform root
2. trigger the controlled failure in Dagster with `should_fail: true`
3. confirm the rule enters firing state
4. confirm the notification reaches the configured contact point

Until that notification lands, the assignment's alerting requirement remains only partially closed.

## 10. Known Recovery Steps

Use these only if the normal bring-up path gets stuck.

### 10.1 Old kubeconfig endpoint

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

## 10. Pre-Destroy Checklist

Before `terraform destroy`, clean up the resources that AWS and Kubernetes do not always tear down quickly enough on their own.

### 10.1 Delete Kubernetes `LoadBalancer` services first

If cluster access still works:

```bash
kubectl get svc -A
kubectl delete svc hydrosat-dagster-webserver -n dagster --ignore-not-found
```

Why:

- Kubernetes-created AWS load balancers can outlive the cluster for several minutes
- their ENIs and security groups block subnet, internet gateway, and VPC deletion

Current recommendation:

- keep this `LoadBalancer` cleanup step because Dagster still uses direct `LoadBalancer` exposure in the exercise profile
- revisit this section only after a shared ingress controller replaces the current external-access path

### 10.2 Verify the AWS load balancer is gone

```bash
aws elb describe-load-balancers --region us-east-1 --output table

aws ec2 describe-network-interfaces \
  --region us-east-1 \
  --filters Name=vpc-id,Values=<vpc-id> \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,Status,Description,Association.PublicIp,SubnetId]' \
  --output table
```

Expected result:

- no classic ELB remains for `hydrosat-dagster-webserver`
- no ELB ENIs remain in the public subnets

If the cluster is already gone and you still see the ELB, delete it directly:

```bash
aws elb delete-load-balancer --region us-east-1 --load-balancer-name <name>
```

### 10.3 Empty versioned S3 buckets

Before destroy, empty any versioned buckets managed by Terraform:

```bash
BUCKET=hydrosat-dev-data-lake-logs

aws s3api delete-objects \
  --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --output json | jq '{Objects: ((.Versions // []) + (.DeleteMarkers // [])) | map({Key:.Key,VersionId:.VersionId}), Quiet: true}')"
```

If needed, repeat for:

- `hydrosat-dev-data-lake`

Why:

- Terraform cannot delete non-empty versioned buckets
- object versions and delete markers both block bucket deletion

### 10.4 Then run destroy

```bash
terraform -chdir=terraform destroy
```

If the VPC still sticks in `Destroying`, inspect:

```bash
aws ec2 describe-network-interfaces --region us-east-1 --filters Name=vpc-id,Values=<vpc-id> --output table
aws ec2 describe-security-groups --region us-east-1 --filters Name=vpc-id,Values=<vpc-id> --output table
aws ec2 describe-nat-gateways --region us-east-1 --filter Name=vpc-id,Values=<vpc-id> --output table
```

## 11. Recommended Validation End State

The environment is in a good state when all of these are true:

- `kubectl get applications -n argocd` shows the platform apps healthy enough for demo use
- `kubectl get externalsecret -A` shows all required secrets synced
- `kubectl get pods -n dagster` shows Dagster workloads running
- `kubectl get pods -n monitoring` shows Alloy running
- Dagster is reachable by port-forward

## 12. Scale Down or Destroy After Validation

If you only need a short validation window:

- scale the node group back down in local `terraform.tfvars`
- or destroy the stack entirely

Commands:

```bash
terraform -chdir=terraform apply
terraform -chdir=terraform destroy
```

Use destroy when you are done and want to eliminate AWS cost completely.
