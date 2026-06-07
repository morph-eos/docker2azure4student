#!/usr/bin/env python3
"""Emit key=value pairs extracted from terraform.tfvars.

Usage:
    python scripts/tfvars_meta.py [path] [key1 key2 ...]

Keys can be suffixed with "=<default>" to make them optional:
    python scripts/tfvars_meta.py terraform.tfvars subscription_id blob_storage_enabled=false

The script prints one "key=value" line per requested key. It fails
if any required key (without a default) is missing or if the file cannot be read.
"""

from __future__ import annotations

import pathlib
import re
import sys
from typing import Iterable

DEFAULT_KEYS = ("subscription_id", "environment_name")

# Keys that are optional and have a built-in default value.
OPTIONAL_DEFAULTS: dict[str, str] = {
    "blob_storage_enabled": "false",
}


def read_tfvars(path: pathlib.Path) -> str:
    try:
        return path.read_text()
    except FileNotFoundError as exc:
        raise SystemExit(f"terraform tfvars file not found: {path}") from exc


def clean_value(raw: str) -> str:
    value = raw.strip()
    # Drop inline comments (simple heuristic: anything after #)
    if "#" in value:
        value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    return value.strip()


def extract_values(content: str, keys: Iterable[str]) -> list[str]:
    results: list[str] = []
    for raw_key in keys:
        # Support "key=default" syntax for ad-hoc optional keys
        if "=" in raw_key:
            key, inline_default = raw_key.split("=", 1)
        else:
            key = raw_key
            inline_default = OPTIONAL_DEFAULTS.get(key)  # type: ignore[assignment]
        pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.+)$", re.MULTILINE)
        match = pattern.search(content)
        if not match:
            if inline_default is not None:
                results.append(f"{key}={inline_default}")
                continue
            raise SystemExit(f"Missing '{key}' in terraform.tfvars")
        value = clean_value(match.group(1))
        results.append(f"{key}={value}")
    return results


def main(argv: list[str]) -> None:
    if len(argv) >= 2 and not argv[1].startswith("-"):
        tfvars_path = pathlib.Path(argv[1])
        keys = argv[2:] or DEFAULT_KEYS
    else:
        tfvars_path = pathlib.Path("terraform.tfvars")
        keys = argv[1:] or DEFAULT_KEYS

    content = read_tfvars(tfvars_path)
    for line in extract_values(content, keys):
        print(line)


if __name__ == "__main__":
    main(sys.argv)
