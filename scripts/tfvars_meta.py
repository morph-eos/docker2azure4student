#!/usr/bin/env python3
"""Emit key=value pairs extracted from terraform.tfvars.

Usage:
    python scripts/tfvars_meta.py [path] [key1 key2 ...]

The script prints one "key=value" line per requested key. It fails
if any key is missing or if the file cannot be read.
"""

from __future__ import annotations

import pathlib
import re
import sys
from typing import Iterable

DEFAULT_KEYS = ("subscription_id", "environment_name")


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
    for key in keys:
        pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.+)$", re.MULTILINE)
        match = pattern.search(content)
        if not match:
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
