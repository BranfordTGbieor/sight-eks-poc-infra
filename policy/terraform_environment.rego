package main

deny[msg] {
  item := input.environment_examples[_]
  not item.exists
  msg := sprintf("Missing local dev tfvars example: %s", [item.path])
}

deny[msg] {
  item := input.environment_examples[_]
  item.exists
  item.declared_environment != item.environment
  msg := sprintf("%s must declare environment = \"%s\"", [item.path, item.environment])
}

deny[msg] {
  item := input.backend_examples[_]
  not item.exists
  msg := sprintf("Missing local dev backend example: %s", [item.path])
}

deny[msg] {
  item := input.backend_examples[_]
  item.exists
  item.key != sprintf("%s/platform.tfstate", [item.environment])
  msg := sprintf("%s must use key = \"%s/platform.tfstate\"", [item.path, item.environment])
}

deny[msg] {
  item := input.backend_examples[_]
  item.exists
  item.region != input.allowed_region
  msg := sprintf("%s must use region = \"%s\"", [item.path, input.allowed_region])
}

deny[msg] {
  item := input.workflow_environment_resolvers[_]
  not item.uses_shared_resolver
  msg := sprintf("%s must use scripts/terraform/resolve-environment.sh for environment mapping", [item.path])
}

deny[msg] {
  expected := {"main", "test", "prod"}
  actual := {branch | branch := input.ci_push_branches[_]}
  actual != expected
  msg := sprintf("CI push branches must be exactly main, test, and prod. Found: %v", [input.ci_push_branches])
}

deny[msg] {
  item := input.region_examples[_]
  item.value != input.allowed_region
  msg := sprintf("%s must use the allowed region %s", [item.path, input.allowed_region])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.node_desired_size > input.max_dev_node_count
  msg := sprintf("%s sets node_desired_size=%v, which exceeds the dev limit of %v", [item.path, item.node_desired_size, input.max_dev_node_count])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.node_min_size > input.max_dev_node_count
  msg := sprintf("%s sets node_min_size=%v, which exceeds the dev limit of %v", [item.path, item.node_min_size, input.max_dev_node_count])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.node_max_size > input.max_dev_node_count
  msg := sprintf("%s sets node_max_size=%v, which exceeds the dev limit of %v", [item.path, item.node_max_size, input.max_dev_node_count])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.db_instance_class == ""
  msg := sprintf("%s must declare db_instance_class for dev cost guardrails", [item.path])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.db_instance_class != ""
  not allowed_dev_db_class(item.db_instance_class)
  msg := sprintf("%s uses unsupported dev db_instance_class %s", [item.path, item.db_instance_class])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.db_multi_az
  msg := sprintf("%s must keep db_multi_az = false for the dev baseline", [item.path])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.db_enable_performance_insights
  msg := sprintf("%s must keep db_enable_performance_insights = false for the dev baseline", [item.path])
}

deny[msg] {
  item := input.dev_cost_examples[_]
  item.db_enable_enhanced_monitoring
  msg := sprintf("%s must keep db_enable_enhanced_monitoring = false for the dev baseline", [item.path])
}

deny[msg] {
  not input.tag_contract.has_project_tag
  msg := "terraform/main.tf must include the Project common tag"
}

deny[msg] {
  not input.tag_contract.has_environment_tag
  msg := "terraform/main.tf must include the Environment common tag"
}

deny[msg] {
  not input.tag_contract.has_managed_by_tag
  msg := "terraform/main.tf must include ManagedBy = \"terraform\" in common tags"
}

deny[msg] {
  not input.tag_contract.has_repository_tag
  msg := "terraform/main.tf must include Repository = \"sight-poc-infra\" in common tags"
}

deny[msg] {
  not input.tag_contract.uses_project_environment_prefix
  msg := "terraform/main.tf must derive resource prefixes from project_name and environment"
}

deny[msg] {
  hit := input.example_account_id_hits[_]
  msg := sprintf("Example config must not contain hardcoded AWS account IDs in %s: %v", [hit.path, hit.matches])
}

deny[msg] {
  hit := input.tracked_file_account_id_hits[_]
  msg := sprintf("Committed config still contains hardcoded AWS account IDs in %s: %v", [hit.path, hit.matches])
}

allowed_dev_db_class(class) {
  input.allowed_dev_db_classes[_] == class
}
