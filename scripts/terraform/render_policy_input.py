#!/usr/bin/env python3
"""Build the structured JSON input consumed by the repo's Conftest policies."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LOCAL_ENV_EXAMPLES = ["dev"]
ALLOWED_REGION = "us-east-1"
DEV_COST_ALLOWED_DB_CLASSES = {
    "db.t3.micro",
    "db.t3.small",
    "db.t4g.micro",
    "db.t4g.small",
}
MAX_DEV_NODE_COUNT = 3
TFVARS_ENV_PATTERN = re.compile(r'^environment\s*=\s*"([^"]+)"$', re.MULTILINE)
TFVARS_REGION_PATTERN = re.compile(r'^aws_region\s*=\s*"([^"]+)"$', re.MULTILINE)
BACKEND_KEY_PATTERN = re.compile(r'^key\s*=\s*"([^"]+)"$', re.MULTILINE)
BACKEND_REGION_PATTERN = re.compile(r'^region\s*=\s*"([^"]+)"$', re.MULTILINE)
STRING_SETTING_PATTERN = re.compile(r'^(?P<key>[A-Za-z0-9_]+)\s*=\s*"(?P<value>[^"]*)"$', re.MULTILINE)
NUMBER_SETTING_PATTERN = re.compile(r'^(?P<key>[A-Za-z0-9_]+)\s*=\s*(?P<value>\d+)$', re.MULTILINE)
BOOL_SETTING_PATTERN = re.compile(r'^(?P<key>[A-Za-z0-9_]+)\s*=\s*(?P<value>true|false)$', re.MULTILINE)
ACCOUNT_ID_PATTERN = re.compile(r'\b\d{12}\b')
PUSH_BRANCHES_PATTERN = re.compile(r'on:\n(?:.|\n)*?push:\n(?:.|\n)*?branches:\n((?:\s+- .*\n)+)', re.MULTILINE)
BRANCH_ENTRY_PATTERN = re.compile(r'^\s+-\s+(.+)$', re.MULTILINE)
VARIABLE_BLOCK_PATTERN = re.compile(r'variable\s+"(?P<name>[^"]+)"\s*\{(?P<body>.*?)\n\}', re.DOTALL)
DEFAULT_STRING_PATTERN = re.compile(r'default\s*=\s*"([^"]+)"')


def read_text(path: Path) -> str:
    """Read UTF-8 text from a repo-relative path."""
    return path.read_text(encoding="utf-8")


def git_tracked_files(*paths: str) -> list[str]:
    """Return tracked files beneath the provided repo-relative paths."""
    cmd = ["git", "ls-files", *paths]
    output = subprocess.check_output(cmd, cwd=REPO_ROOT, text=True)
    return [line for line in output.splitlines() if line]


def parse_string_settings(text: str) -> dict[str, str]:
    """Parse top-level Terraform string assignments from an example file."""
    return {match.group("key"): match.group("value") for match in STRING_SETTING_PATTERN.finditer(text)}


def parse_number_settings(text: str) -> dict[str, int]:
    """Parse top-level Terraform numeric assignments from an example file."""
    return {match.group("key"): int(match.group("value")) for match in NUMBER_SETTING_PATTERN.finditer(text)}


def parse_bool_settings(text: str) -> dict[str, bool]:
    """Parse top-level Terraform boolean assignments from an example file."""
    return {match.group("key"): match.group("value") == "true" for match in BOOL_SETTING_PATTERN.finditer(text)}


def collect_environment_examples() -> list[dict[str, str]]:
    """Collect existence and declared environment data for local tfvars examples."""
    items: list[dict[str, str]] = []
    for env in LOCAL_ENV_EXAMPLES:
        path = REPO_ROOT / "terraform" / "environments" / f"{env}.tfvars.example"
        declared_environment = ""
        if path.exists():
            match = TFVARS_ENV_PATTERN.search(read_text(path))
            declared_environment = match.group(1) if match else ""
        items.append(
            {
                "environment": env,
                "path": str(path.relative_to(REPO_ROOT)),
                "exists": path.exists(),
                "declared_environment": declared_environment,
            }
        )
    return items


def collect_backend_examples() -> list[dict[str, str]]:
    """Collect existence, state key, and region data for backend examples."""
    items: list[dict[str, str]] = []
    for env in LOCAL_ENV_EXAMPLES:
        path = REPO_ROOT / "terraform" / "environments" / f"{env}.platform.backend.hcl.example"
        backend_key = ""
        region = ""
        if path.exists():
            text = read_text(path)
            key_match = BACKEND_KEY_PATTERN.search(text)
            region_match = BACKEND_REGION_PATTERN.search(text)
            backend_key = key_match.group(1) if key_match else ""
            region = region_match.group(1) if region_match else ""
        items.append(
            {
                "environment": env,
                "path": str(path.relative_to(REPO_ROOT)),
                "exists": path.exists(),
                "key": backend_key,
                "region": region,
            }
        )
    return items


def collect_workflow_resolvers() -> list[dict[str, object]]:
    """Verify that relevant workflows reuse the shared environment resolver."""
    workflow_paths = [
        ".github/workflows/ci.yml",
        ".github/workflows/terraform-delivery.yml",
        ".github/workflows/grafana-alerting-delivery.yml",
    ]
    items = []
    for rel_path in workflow_paths:
        text = read_text(REPO_ROOT / rel_path)
        items.append(
            {
                "path": rel_path,
                "uses_shared_resolver": "./scripts/terraform/resolve-environment.sh" in text,
            }
        )
    return items


def collect_ci_push_branches() -> list[str]:
    """Extract the branch list declared under the CI workflow's push trigger."""
    text = read_text(REPO_ROOT / ".github/workflows/ci.yml")
    match = PUSH_BRANCHES_PATTERN.search(text)
    if not match:
        return []
    block = match.group(1)
    return [entry.strip().strip('"').strip("'") for entry in BRANCH_ENTRY_PATTERN.findall(block)]


def collect_account_id_hits() -> list[dict[str, object]]:
    """Find hardcoded AWS account IDs in tracked, non-example config files."""
    tracked_paths = [
        path
        for path in git_tracked_files("terraform", "gitops", "helm/dagster/values-gitops.yaml")
        if not path.endswith(".example")
    ]
    hits: list[dict[str, object]] = []
    for rel_path in tracked_paths:
        text = read_text(REPO_ROOT / rel_path)
        matches = sorted(set(ACCOUNT_ID_PATTERN.findall(text)))
        if matches:
            hits.append({"path": rel_path, "matches": matches})
    return hits


def collect_example_account_id_hits() -> list[dict[str, object]]:
    """Find hardcoded AWS account IDs in developer-facing example files."""
    example_paths = [
        "terraform/terraform.tfvars.example",
        "terraform/environments/dev.tfvars.example",
        "terraform/backend.hcl.example",
        "terraform/environments/dev.platform.backend.hcl.example",
    ]
    hits: list[dict[str, object]] = []
    for rel_path in example_paths:
        path = REPO_ROOT / rel_path
        if not path.exists():
            continue
        matches = sorted(set(ACCOUNT_ID_PATTERN.findall(read_text(path))))
        if matches:
            hits.append({"path": rel_path, "matches": matches})
    return hits


def collect_region_examples() -> list[dict[str, str]]:
    """Collect region declarations from variables and example files."""
    items: list[dict[str, str]] = []
    example_paths = [
        "terraform/variables.tf",
        "terraform/terraform.tfvars.example",
        "terraform/environments/dev.tfvars.example",
        "terraform/backend.hcl.example",
        "terraform/environments/dev.platform.backend.hcl.example",
    ]
    for rel_path in example_paths:
        path = REPO_ROOT / rel_path
        if not path.exists():
            continue
        text = read_text(path)
        if rel_path.endswith("variables.tf"):
            aws_region_block = None
            for candidate in VARIABLE_BLOCK_PATTERN.finditer(text):
                if candidate.group("name") == "aws_region":
                    aws_region_block = candidate.group("body")
                    break
            value = ""
            if aws_region_block:
                default_match = DEFAULT_STRING_PATTERN.search(aws_region_block)
                value = default_match.group(1) if default_match else ""
            items.append({"path": rel_path, "value": value})
            continue
        region_match = TFVARS_REGION_PATTERN.search(text) or BACKEND_REGION_PATTERN.search(text)
        items.append({"path": rel_path, "value": region_match.group(1) if region_match else ""})
    return items


def collect_dev_cost_examples() -> list[dict[str, object]]:
    """Collect the dev-only cost-sensitive settings from example tfvars files."""
    items: list[dict[str, object]] = []
    example_paths = [
        "terraform/terraform.tfvars.example",
        "terraform/environments/dev.tfvars.example",
    ]
    for rel_path in example_paths:
        path = REPO_ROOT / rel_path
        if not path.exists():
            continue
        text = read_text(path)
        string_settings = parse_string_settings(text)
        number_settings = parse_number_settings(text)
        bool_settings = parse_bool_settings(text)
        items.append(
            {
                "path": rel_path,
                "node_desired_size": number_settings.get("node_desired_size"),
                "node_min_size": number_settings.get("node_min_size"),
                "node_max_size": number_settings.get("node_max_size"),
                "db_instance_class": string_settings.get("db_instance_class", ""),
                "db_multi_az": bool_settings.get("db_multi_az"),
                "db_enable_performance_insights": bool_settings.get("db_enable_performance_insights"),
                "db_enable_enhanced_monitoring": bool_settings.get("db_enable_enhanced_monitoring"),
            }
        )
    return items


def collect_tag_contract() -> dict[str, object]:
    """Check that the Terraform root defines the common tag contract."""
    text = read_text(REPO_ROOT / "terraform/main.tf")
    return {
        "has_project_tag": 'Project     = var.project_name' in text,
        "has_environment_tag": 'Environment = var.environment' in text,
        "has_managed_by_tag": 'ManagedBy   = "terraform"' in text,
        "has_repository_tag": 'Repository  = "sight-poc-infra"' in text,
        "uses_project_environment_prefix": 'name = "${var.project_name}-${var.environment}"' in text,
    }


payload = {
    "allowed_region": ALLOWED_REGION,
    "allowed_dev_db_classes": sorted(DEV_COST_ALLOWED_DB_CLASSES),
    "max_dev_node_count": MAX_DEV_NODE_COUNT,
    "local_environment_examples": LOCAL_ENV_EXAMPLES,
    "environment_examples": collect_environment_examples(),
    "backend_examples": collect_backend_examples(),
    "workflow_environment_resolvers": collect_workflow_resolvers(),
    "ci_push_branches": collect_ci_push_branches(),
    "tracked_file_account_id_hits": collect_account_id_hits(),
    "example_account_id_hits": collect_example_account_id_hits(),
    "region_examples": collect_region_examples(),
    "dev_cost_examples": collect_dev_cost_examples(),
    "tag_contract": collect_tag_contract(),
}

print(json.dumps(payload, indent=2, sort_keys=True))
