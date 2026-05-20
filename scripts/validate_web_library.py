#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


ABSOLUTE_LOCAL_PATH_RE = re.compile(r"^(?:/|[A-Za-z]:[\\/]|\\\\|file://)", re.IGNORECASE)
JSON_PATH_RE = re.compile(r'(?i)(?:/|\\\\)[^"\n]*\.(?:dat|lvm)(?=$|[^A-Za-z0-9_])')


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_output_dir() -> Path:
    return repo_root().parent / "SpinLab-Web-Library" / "public"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the exported SpinLab web library bundle.")
    parser.add_argument(
        "--output-dir",
        default=str(default_output_dir()),
        help="Export output directory to validate (default: ../SpinLab-Web-Library/public)",
    )
    parser.add_argument("--verbose", action="store_true", help="Print validation progress")
    return parser.parse_args()


def load_json(path: Path, errors: list[str]) -> Any | None:
    if not path.exists():
        errors.append(f"Missing required JSON file: {path}")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"Invalid JSON in {path}: {exc.msg} (line {exc.lineno}, column {exc.colno})")
        return None


def iter_json_files(output_dir: Path) -> Iterable[Path]:
    if not output_dir.exists():
        return []
    return sorted(path for path in output_dir.rglob("*.json") if path.is_file())


def is_absolute_local_path(value: str) -> bool:
    return bool(ABSOLUTE_LOCAL_PATH_RE.match(value.strip()))


def validate_asset_key(value: Any, context: str, errors: list[str]) -> None:
    if not isinstance(value, str):
        errors.append(f"{context}.asset_key must be a string")
        return
    text = value.strip()
    if not text:
        errors.append(f"{context}.asset_key must be non-empty")
    if text.startswith(("http://", "https://")):
        errors.append(f"{context}.asset_key must not start with http:// or https://")
    if "/Users/" in text:
        errors.append(f"{context}.asset_key must not contain /Users/")
    if is_absolute_local_path(text):
        errors.append(f"{context}.asset_key must not be an absolute local path")


def validate_url(value: Any, context: str, errors: list[str]) -> None:
    if not isinstance(value, str):
        errors.append(f"{context}.url must be a string")
        return
    text = value.strip()
    if not text:
        errors.append(f"{context}.url must be non-empty")
    if "/Users/" in text:
        errors.append(f"{context}.url must not contain /Users/")
    if is_absolute_local_path(text):
        errors.append(f"{context}.url must not be an absolute local path")


def validate_chart_assets(report: Any, errors: list[str]) -> None:
    if not isinstance(report, dict):
        errors.append("data/export_report.json must contain a JSON object")
        return

    asset_stats = report.get("assetStats")
    if not isinstance(asset_stats, dict):
        errors.append("data/export_report.json must contain assetStats")
        return

    assets = asset_stats.get("assets")
    if not isinstance(assets, list):
        errors.append("data/export_report.json assetStats.assets must be a list")
        return

    for index, asset in enumerate(assets):
        context = f"data/export_report.json assetStats.assets[{index}]"
        if not isinstance(asset, dict):
            errors.append(f"{context} must be an object")
            continue
        if "asset_key" not in asset:
            errors.append(f"{context} must contain asset_key")
        else:
            validate_asset_key(asset.get("asset_key"), context, errors)
        if "url" not in asset:
            errors.append(f"{context} must contain url")
        else:
            validate_url(asset.get("url"), context, errors)


def validate_frontend(app_js: Path, errors: list[str]) -> None:
    if not app_js.exists():
        errors.append(f"Missing required frontend file: {app_js}")
        return

    text = app_js.read_text(encoding="utf-8")
    chart_block_start = text.find("function renderCharts(sample) {")
    chart_block_end = text.find("function renderDetail() {")
    chart_block = text[chart_block_start:chart_block_end] if chart_block_start != -1 and chart_block_end != -1 else text

    if 'src="${escapeHtml(chart.url)}"' not in chart_block:
        errors.append("public/app.js must render chart images using chart.url")

    if "assets/" in text:
        errors.append("public/app.js must not hard-code assets/ image paths")

    if re.search(r'src="[^"]*(?:asset_key|sample|batch|assets/)[^"]*"', chart_block):
        errors.append("public/app.js must not build chart image paths from asset_key, sample, batch, or assets/")


def validate_output_directory(output_dir: Path, verbose: bool) -> list[str]:
    errors: list[str] = []
    if verbose:
        print(f"[validate-web] validating {output_dir}")

    if not output_dir.exists():
        errors.append(f"Missing output directory: {output_dir}")
        return errors
    if not output_dir.is_dir():
        errors.append(f"Output path is not a directory: {output_dir}")
        return errors

    library_json = output_dir / "data" / "library.json"
    report_json = output_dir / "data" / "export_report.json"
    app_js = output_dir / "app.js"

    library_data = load_json(library_json, errors)
    report_data = load_json(report_json, errors)

    if library_data is not None and not isinstance(library_data, dict):
        errors.append("data/library.json must contain a JSON object")

    validate_chart_assets(report_data, errors)
    validate_frontend(app_js, errors)

    for json_path in iter_json_files(output_dir):
        try:
            raw_text = json_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"Unable to read JSON file {json_path}: {exc}")
            continue
        if "/Users/jack/" in raw_text:
            errors.append(f"{json_path} must not contain /Users/jack/")
        if JSON_PATH_RE.search(raw_text):
            errors.append(f"{json_path} must not contain raw .dat or .lvm paths")

    forbidden_files = [
        path
        for path in output_dir.rglob("*")
        if path.is_file() and path.suffix.lower() in {".dat", ".lvm"}
    ]
    for path in forbidden_files:
        errors.append(f"public/ must not contain {path.suffix.lower()} files: {path}")

    return errors


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir).expanduser().resolve()
    errors = validate_output_directory(output_dir, args.verbose)

    if errors:
        print("Web Library validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Web Library validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
