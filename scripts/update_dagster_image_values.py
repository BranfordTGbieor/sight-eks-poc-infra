#!/usr/bin/env python3
"""Update the promoted Dagster image reference in the GitOps values file."""
from __future__ import annotations

import os
from pathlib import Path


VALUES_PATH = Path(__file__).resolve().parent.parent / "helm" / "dagster" / "values-gitops.yaml"


def replace_line(content: str, prefix: str, value: str) -> str:
    """Replace a single prefixed YAML line while preserving the rest of the file."""
    for line in content.splitlines():
        if line.startswith(prefix):
            break
    else:
        raise SystemExit(f"Unable to find line starting with {prefix!r} in {VALUES_PATH}.")

    updated_lines = []
    for line in content.splitlines():
        if line.startswith(prefix):
            updated_lines.append(f"{prefix}{value}")
        else:
            updated_lines.append(line)
    return "\n".join(updated_lines) + "\n"


def main() -> None:
    """Apply the CI-provided image repository and tag to values-gitops.yaml."""
    image_repository = os.environ["IMAGE_REPOSITORY"]
    image_tag = os.environ["IMAGE_TAG"]

    content = VALUES_PATH.read_text(encoding="utf-8")
    content = replace_line(content, "  repository: ", image_repository)
    content = replace_line(content, "  tag: ", image_tag)
    VALUES_PATH.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
