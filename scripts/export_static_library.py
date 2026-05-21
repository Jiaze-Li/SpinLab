#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote


IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"}

WARN_CHART_BYTES = 200 * 1024 * 1024
FAIL_CHART_BYTES = 500 * 1024 * 1024
WARN_IMAGE_BYTES = 5 * 1024 * 1024
FAIL_IMAGE_BYTES = 20 * 1024 * 1024
WARN_IMAGE_COUNT = 2000
FAIL_IMAGE_COUNT = 5000


@dataclass(frozen=True)
class AssetRecord:
    asset_key: str
    url: str
    sample_key: str | None
    source_file: str
    size_bytes: int
    source_relpath: str
    source_path: Path
    destination_path: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export SpinLab library data to a static web bundle.")
    parser.add_argument("--library-root", required=True, help="Root directory containing index/ and samples/")
    parser.add_argument("--output-dir", required=True, help="Destination directory for the static export")
    parser.add_argument("--force", action="store_true", help="Allow export to continue past hard asset thresholds")
    return parser.parse_args()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def ensure_inside(base_dir: Path, candidate: Path) -> None:
    base = base_dir.resolve()
    target = candidate.resolve()
    if base == target:
        return
    try:
        target.relative_to(base)
    except ValueError as exc:
        raise RuntimeError(f"Refusing to write outside output dir: {target}") from exc


def safe_slug(value: str) -> str:
    slug = [ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in value]
    cleaned = "".join(slug).strip("_")
    return cleaned or "item"


def short_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def natural_key(value: str) -> list[Any]:
    parts = re.split(r"(\d+)", value)
    key: list[Any] = []
    for part in parts:
        if not part:
            continue
        if part.isdigit():
            key.append(int(part))
        else:
            key.append(part.casefold())
    return key


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def collect_images(library_root: Path, output_dir: Path) -> list[Path]:
    images: list[Path] = []
    output_resolved = output_dir.resolve()
    for path in library_root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue
        try:
            if output_resolved in path.resolve().parents or path.resolve() == output_resolved:
                continue
        except FileNotFoundError:
            continue
        images.append(path)
    return sorted(images)


def infer_sample_key(library_root: Path, source_path: Path) -> str | None:
    rel = source_path.relative_to(library_root)
    parts = rel.parts
    if not parts:
        return None
    if parts[0] == "samples" and len(parts) >= 2:
        return parts[1]
    if parts[0] == "_spinlab" and len(parts) >= 2 and parts[1] == "multi-sample":
        return "multi-sample"
    if parts[0] == "batches" and "samples" in parts:
        idx = parts.index("samples")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return None


def build_asset_records(library_root: Path, output_dir: Path, images: Iterable[Path]) -> list[AssetRecord]:
    records: list[AssetRecord] = []
    assets_dir = output_dir / "assets"
    for source_path in images:
        rel = source_path.relative_to(library_root)
        sample_key = infer_sample_key(library_root, source_path)
        source_file = source_path.name
        rel_text = rel.as_posix()
        digest = short_hash(rel_text)
        ext = source_path.suffix.lower()
        file_name = f"{safe_slug(sample_key or 'orphan')}--{digest}{ext}"
        destination_path = assets_dir / file_name
        asset_key = f"{sample_key or 'orphan'}::{source_file}::{digest}"
        url = f"assets/{quote(file_name)}"
        records.append(
            AssetRecord(
                asset_key=asset_key,
                url=url,
                sample_key=sample_key,
                source_file=source_file,
                size_bytes=source_path.stat().st_size,
                source_relpath=rel_text,
                source_path=source_path,
                destination_path=destination_path,
            )
        )
    return records


def load_sample_chart_order_map(library_root: Path) -> dict[str, dict[str, int]]:
    order_map: dict[str, dict[str, int]] = {}
    samples_dir = library_root / "samples"
    if not samples_dir.exists():
        return order_map

    for sample_dir in samples_dir.iterdir():
        if not sample_dir.is_dir():
            continue
        sample_key = sample_dir.name
        index_path = sample_dir / "_spinlab" / "results_index.json"
        if not index_path.exists():
            continue
        try:
            index = read_json(index_path)
        except Exception:
            continue
        references = index.get("references", [])
        if not isinstance(references, list) or not references:
            continue
        sample_order: dict[str, int] = {}
        for idx, reference in enumerate(references):
            if not isinstance(reference, dict):
                continue
            chart_path = reference.get("chartImagePath")
            if isinstance(chart_path, str) and chart_path:
                sample_order[chart_path] = idx
        if sample_order:
            order_map[sample_key] = sample_order
    return order_map


def sort_asset_records(
    asset_records: list[AssetRecord],
    chart_order_map: dict[str, dict[str, int]],
) -> list[AssetRecord]:
    def sort_key(record: AssetRecord) -> tuple[Any, ...]:
        sample_key = record.sample_key or ""
        sample_bucket = 0 if sample_key else 1
        order_map = chart_order_map.get(sample_key, {})
        chart_order = order_map.get(record.source_relpath)
        fallback_title = Path(record.source_relpath).stem
        return (
            sample_bucket,
            natural_key(sample_key),
            0 if chart_order is not None else 1,
            chart_order if chart_order is not None else 0,
            natural_key(fallback_title),
            record.source_relpath,
        )

    return sorted(asset_records, key=sort_key)


def summarize_thresholds() -> dict[str, int]:
    return {
        "chartBytesWarn": WARN_CHART_BYTES,
        "chartBytesFail": FAIL_CHART_BYTES,
        "imageBytesWarn": WARN_IMAGE_BYTES,
        "imageBytesFail": FAIL_IMAGE_BYTES,
        "imageCountWarn": WARN_IMAGE_COUNT,
        "imageCountFail": FAIL_IMAGE_COUNT,
    }


def build_warnings_and_errors(asset_records: list[AssetRecord]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    warnings: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    total_bytes = sum(record.size_bytes for record in asset_records)
    count = len(asset_records)
    largest = max(asset_records, key=lambda record: record.size_bytes, default=None)

    if total_bytes > WARN_CHART_BYTES:
        warnings.append(
            {
                "code": "chart_bytes_warn",
                "message": "Total chart assets exceed the warning threshold.",
                "value": total_bytes,
                "limit": WARN_CHART_BYTES,
            }
        )
    if total_bytes > FAIL_CHART_BYTES:
        errors.append(
            {
                "code": "chart_bytes_fail",
                "message": "Total chart assets exceed the hard limit.",
                "value": total_bytes,
                "limit": FAIL_CHART_BYTES,
            }
        )

    if largest and largest.size_bytes > WARN_IMAGE_BYTES:
        warnings.append(
            {
                "code": "image_bytes_warn",
                "message": "At least one image exceeds the warning threshold.",
                "asset_key": largest.asset_key,
                "value": largest.size_bytes,
                "limit": WARN_IMAGE_BYTES,
            }
        )
    if largest and largest.size_bytes > FAIL_IMAGE_BYTES:
        errors.append(
            {
                "code": "image_bytes_fail",
                "message": "At least one image exceeds the hard limit.",
                "asset_key": largest.asset_key,
                "value": largest.size_bytes,
                "limit": FAIL_IMAGE_BYTES,
            }
        )

    if count > WARN_IMAGE_COUNT:
        warnings.append(
            {
                "code": "image_count_warn",
                "message": "Image count exceeds the warning threshold.",
                "value": count,
                "limit": WARN_IMAGE_COUNT,
            }
        )
    if count > FAIL_IMAGE_COUNT:
        errors.append(
            {
                "code": "image_count_fail",
                "message": "Image count exceeds the hard limit.",
                "value": count,
                "limit": FAIL_IMAGE_COUNT,
            }
        )

    return warnings, errors


def clean_generated_output(output_dir: Path) -> None:
    for name in ["index.html", "styles.css", "app.js"]:
        path = output_dir / name
        if path.exists():
            path.unlink()
    for name in ["data", "assets"]:
        path = output_dir / name
        if path.exists():
            shutil.rmtree(path)


def web_library_template_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "Resources" / "WebLibraryTemplate"


def read_web_library_template(name: str) -> str:
    template_path = web_library_template_dir() / name
    if not template_path.exists():
        raise RuntimeError(f"Missing Web Library template: {template_path}")
    return template_path.read_text(encoding="utf-8")


def write_web_library_templates(output_dir: Path) -> None:
    # Web Library UI source of truth is Resources/WebLibraryTemplate/.
    # ../SpinLab-Web-Library/public/ is generated output and may be replaced on every publish.
    # Do not edit generated public files directly.
    for name in ["index.html", "styles.css", "app.js"]:
        (output_dir / name).write_text(read_web_library_template(name), encoding="utf-8")


def gather_string_list(values: Iterable[Any]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        text = str(value)
        if text in seen:
            continue
        seen.add(text)
        output.append(text)
    return sorted(output)


def build_library_export(
    index: dict[str, Any],
    asset_records: list[AssetRecord],
    source_root: Path,
) -> dict[str, Any]:
    batches = index.get("batches", [])
    samples = index.get("samples", [])

    batch_ids = gather_string_list(batch.get("id", "") for batch in batches if batch.get("id"))
    sheet_names = gather_string_list(
        value for value in (sample.get("sourceSheetName") or sample.get("sheetName") for sample in samples) if value
    )
    substrates = gather_string_list(sample.get("substrateDisplay") or sample.get("substrateRaw") for sample in samples if sample.get("substrateDisplay") or sample.get("substrateRaw"))
    numeric_tag_names = gather_string_list(
        key for sample in samples for key in (sample.get("numericTags") or {}).keys()
    )
    metadata_keys = gather_string_list(
        key for sample in samples for key in (sample.get("metadata") or {}).keys()
    )
    asset_groups = gather_string_list(record.sample_key for record in asset_records if record.sample_key)

    chart_bytes = sum(record.size_bytes for record in asset_records)
    chart_count = len(asset_records)

    return {
        "schemaVersion": 1,
        "sourceSummary": {
            "sourceRootName": source_root.name,
            "indexVersion": index.get("version", 1),
            "indexCreatedAt": index.get("createdAt"),
            "indexUpdatedAt": index.get("updatedAt"),
            "batchCount": len(batches),
            "sampleCount": len(samples),
            "chartCount": chart_count,
            "chartBytes": chart_bytes,
            "metadataColumnOrder": index.get("metadataColumnOrder", []),
        },
        "batches": batches,
        "samples": samples,
        "filters": {
            "batchIds": batch_ids,
            "sheetNames": sheet_names,
            "substrates": substrates,
            "numericTagNames": numeric_tag_names,
            "metadataKeys": metadata_keys,
            "assetGroups": asset_groups,
        },
    }


def build_report(
    asset_records: list[AssetRecord],
    warnings: list[dict[str, Any]],
    errors: list[dict[str, Any]],
    forced: bool,
    exported_at: str,
) -> dict[str, Any]:
    total_bytes = sum(record.size_bytes for record in asset_records)
    largest = max(asset_records, key=lambda record: record.size_bytes, default=None)
    sample_keys = gather_string_list(record.sample_key for record in asset_records if record.sample_key)
    return {
        "exportedAt": exported_at,
        "forced": forced,
        "thresholds": summarize_thresholds(),
        "assetStats": {
            "chartCount": len(asset_records),
            "chartBytes": total_bytes,
            "largestChartKey": largest.asset_key if largest else None,
            "largestChartBytes": largest.size_bytes if largest else 0,
            "sampleKeys": sample_keys,
            "assets": [
                {
                    "asset_key": record.asset_key,
                    "url": record.url,
                    "sample_key": record.sample_key,
                    "source_file": record.source_file,
                    "size_bytes": record.size_bytes,
                }
                for record in asset_records
            ],
        },
        "warnings": warnings,
        "errors": errors,
    }


def print_summary(output_dir: Path, report: dict[str, Any]) -> None:
    asset_stats = report["assetStats"]
    warnings = report["warnings"]
    errors = report["errors"]
    print(f"[spinlab-export] wrote {output_dir}")
    print(f"[spinlab-export] charts: {asset_stats['chartCount']} ({asset_stats['chartBytes']} bytes)")
    print(f"[spinlab-export] warnings: {len(warnings)}")
    print(f"[spinlab-export] errors: {len(errors)}")
    if warnings:
        for warning in warnings:
            print(f"[spinlab-export] warning {warning['code']}: {warning['message']}")
    if errors:
        for error in errors:
            print(f"[spinlab-export] error {error['code']}: {error['message']}")


def main() -> int:
    args = parse_args()
    library_root = Path(args.library_root).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    force = bool(args.force)

    if not library_root.exists():
        print(f"[spinlab-export] library root not found: {library_root}", file=sys.stderr)
        return 2

    index_path = library_root / "index" / "library_index.json"
    if not index_path.exists():
        print(f"[spinlab-export] missing library index: {index_path}", file=sys.stderr)
        return 2

    index = read_json(index_path)
    images = collect_images(library_root, output_dir)
    asset_records = build_asset_records(library_root, output_dir, images)
    chart_order_map = load_sample_chart_order_map(library_root)
    asset_records = sort_asset_records(asset_records, chart_order_map)
    warnings, errors = build_warnings_and_errors(asset_records)
    exported_at = utc_now_iso()
    report = build_report(asset_records, warnings, errors, force, exported_at)

    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / "data" / "export_report.json"
    write_json(report_path, report)

    fatal = bool(errors) and not force
    if fatal:
        print_summary(output_dir, report)
        return 1

    clean_generated_output(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    for record in asset_records:
        ensure_inside(output_dir, record.destination_path)
        record.destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(record.source_path, record.destination_path)

    library_export = build_library_export(index, asset_records, library_root)
    write_json(output_dir / "data" / "library.json", library_export)
    write_json(report_path, report)
    write_web_library_templates(output_dir)

    print_summary(output_dir, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
