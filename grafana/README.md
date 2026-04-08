# Grafana Alerting as Code

This Terraform root manages the first Grafana Cloud alerting resources for the Hydrosat exercise without mixing them into the AWS infrastructure state.

Current scope:

- one Grafana folder for provisioned alert rules
- one email contact point
- one notification policy branch for `service=dagster`
- one Grafana-managed alert rule for Dagster `RUN_FAILURE`

Why this root is separate:

- Grafana Cloud credentials and API state are separate from AWS infrastructure
- alerting can evolve without touching the main `terraform/` state
- the first alert pack is small enough to manage independently

## Required Inputs

Copy the example file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Populate:

- `grafana_url`
- `grafana_auth`
- `notification_email_addresses`
- `loki_datasource_uid`

The Grafana token should be a service account token with alerting provisioning permissions. Grafana documents Terraform provisioning for alerting here:

- https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/terraform-provisioning/
- https://grafana.com/docs/grafana-cloud/as-code/infrastructure-as-code/

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Notes

- `grafana_notification_policy` manages the policy tree and can overwrite provisioned policy structure.
- `disable_provenance = false` keeps the Terraform resources authoritative.
- set `disable_provenance = true` only if you explicitly want to keep editing these resources in the Grafana UI.
