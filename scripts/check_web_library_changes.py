#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REPORT_PATH = "public/data/export_report.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check whether the web library export has meaningful changes.")
    parser.add_argument("--repo-dir", required=True, help="Path to the SpinLab-Web-Library git repository")
    return parser.parse_args()


def run_git(repo_dir: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_dir), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def strip_exported_at(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: strip_exported_at(item) for key, item in value.items() if key != "exportedAt"}
    if isinstance(value, list):
        return [strip_exported_at(item) for item in value]
    return value


def load_json_text(text: str) -> Any:
    return json.loads(text)


def has_meaningful_report_change(repo_dir: Path) -> bool:
    public_report = repo_dir / REPORT_PATH
    try:
        working_report = load_json_text(public_report.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return True
    except json.JSONDecodeError:
        return True

    try:
        head_text = run_git(repo_dir, "show", f"HEAD:{REPORT_PATH}")
    except subprocess.CalledProcessError:
        return True

    try:
        head_report = load_json_text(head_text)
    except json.JSONDecodeError:
        return True

    return strip_exported_at(working_report) != strip_exported_at(head_report)


def main() -> int:
    args = parse_args()
    repo_dir = Path(args.repo_dir).expanduser().resolve()

    tracked_changes = run_git(repo_dir, "diff", "--name-only", "--", "public").splitlines()
    untracked_changes = run_git(
        repo_dir,
        "ls-files",
        "--others",
        "--exclude-standard",
        "--",
        "public",
    ).splitlines()
    changed_paths = sorted({path for path in tracked_changes + untracked_changes if path})

    if not changed_paths:
        print("No web snapshot changes to publish.")
        return 0

    if changed_paths == [REPORT_PATH] and not has_meaningful_report_change(repo_dir):
        print("No web snapshot changes to publish.")
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
