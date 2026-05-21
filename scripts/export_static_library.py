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


def resolved_tab_key(chart_path: str, tab_key: str | None) -> str | None:
    if tab_key:
        return tab_key
    filename = Path(chart_path).name
    if filename.startswith("R1ω_") or filename.startswith("R1\u03C9_"):
        return "fieldSweep1omega"
    if filename.startswith("R3ω_") or filename.startswith("R3\u03C9_"):
        return "fieldSweep3omega"
    if filename.startswith("RAHE1ω") or filename.startswith("RAHE1\u03C9"):
        return "rahe1omegaVsT"
    if filename.startswith("RAHE3ω") or filename.startswith("RAHE3\u03C9"):
        return "rahe3omegaVsT"
    if filename.startswith("Hc_"):
        return "hcVsT"
    if filename.startswith("Rxx_vs_T_") or filename.startswith("RT_"):
        return "rtCurve"
    if filename.startswith("Scaling_Law_"):
        return "scaling"
    return None


TAB_RANK = {
    "fieldSweep1omega": 0,
    "fieldSweep3omega": 1,
    "rahe1omegaVsT": 2,
    "rahe3omegaVsT": 3,
    "hcVsT": 4,
    "rtCurve": 5,
    "scaling": 6,
}


def chart_sort_key(ref: dict[str, Any], original_index: int) -> tuple[int, str, int]:
    rank = TAB_RANK.get(resolved_tab_key(str(ref.get("chartImagePath", "")), ref.get("tabKey")), len(TAB_RANK))
    generated_at = str(ref.get("generatedAt") or "")
    return (rank, generated_at, original_index)


def extract_angle_value(*candidates: Any) -> float | None:
    pattern = re.compile(r"(?i)(-?\d+(?:\.\d+)?)\s*(?:deg|degree)")
    for candidate in candidates:
        text = str(candidate or "")
        match = pattern.search(text)
        if match:
            try:
                return float(match.group(1))
            except ValueError:
                continue
    return None


def measurement_group_angle(measurement_source: str, chart_refs: list[dict[str, Any]]) -> float | None:
    candidates: list[Any] = [measurement_source]
    for ref in chart_refs:
        chart_path = ref.get("chartImagePath")
        candidates.append(chart_path)
        candidates.append(Path(str(chart_path or "")).stem)
    return extract_angle_value(*candidates)


def group_angle_for_measurement(
    measurement_source: str,
    chart_keys: list[str],
    refs_by_key: dict[str, dict[str, Any]],
) -> float | None:
    selected_refs: list[dict[str, Any]] = []
    for chart_key in chart_keys:
        ref = refs_by_key.get(chart_key)
        if isinstance(ref, dict):
            selected_refs.append(ref)
    angle = measurement_group_angle(measurement_source, selected_refs)
    if angle is not None:
        return angle
    # If the measurement key is opaque, fall back to any chart title/path evidence.
    for ref in selected_refs:
        angle = extract_angle_value(
            ref.get("chartImagePath"),
            Path(str(ref.get("chartImagePath") or "")).stem,
            ref.get("source_file"),
        )
        if angle is not None:
            return angle
    return None


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


def load_sample_indexes(library_root: Path, sample_key: str) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    sample_dir = library_root / "samples" / sample_key
    results_path = sample_dir / "_spinlab" / "results_index.json"
    plot_path = sample_dir / "_spinlab" / "measurement_plot_index.json"

    results: dict[str, Any] | None = None
    plot: dict[str, Any] | None = None

    try:
        if results_path.exists():
            loaded_results = read_json(results_path)
            if isinstance(loaded_results, dict) and isinstance(loaded_results.get("references"), list):
                results = loaded_results
    except Exception:
        results = None

    try:
        if plot_path.exists():
            loaded_plot = read_json(plot_path)
            if isinstance(loaded_plot, dict) and isinstance(loaded_plot.get("entries"), dict):
                plot = loaded_plot
    except Exception:
        plot = None

    return results, plot


def ordered_chart_paths_for_sample(library_root: Path, sample_key: str) -> list[str]:
    results, plot = load_sample_indexes(library_root, sample_key)

    if results and plot:
        refs_by_key = {
            ref.get("chartIdentityKey"): ref
            for ref in results.get("references", [])
            if isinstance(ref, dict) and isinstance(ref.get("chartIdentityKey"), str)
        }
        seen: set[str] = set()
        ordered_paths: list[str] = []
        grouped_measurements: list[tuple[int, float | None, str, list[str]]] = []
        for insertion_index, (measurement_source, chart_keys) in enumerate(plot["entries"].items()):
            if not isinstance(measurement_source, str) or not isinstance(chart_keys, list):
                continue
            grouped_measurements.append((insertion_index, None, measurement_source, [ck for ck in chart_keys if isinstance(ck, str)]))

        def measurement_sort_key(item: tuple[int, float | None, str, list[str]]) -> tuple[int, float, int, str]:
            insertion_index, angle, measurement_source, chart_keys = item
            if angle is None:
                angle = group_angle_for_measurement(measurement_source, chart_keys, refs_by_key)
            if angle is None:
                return (1, 0.0, insertion_index, measurement_source)
            return (0, float(angle), insertion_index, measurement_source)

        for _, _, measurement_source, chart_keys in sorted(grouped_measurements, key=measurement_sort_key):
            selected: list[tuple[int, dict[str, Any]]] = []
            for original_index, chart_key in enumerate(chart_keys):
                ref = refs_by_key.get(chart_key)
                if isinstance(ref, dict):
                    selected.append((original_index, ref))
            selected.sort(key=lambda item: chart_sort_key(item[1], item[0]))
            for _, ref in selected:
                chart_key = ref.get("chartIdentityKey")
                chart_path = ref.get("chartImagePath")
                if not isinstance(chart_key, str) or not isinstance(chart_path, str):
                    continue
                if chart_key in seen:
                    continue
                seen.add(chart_key)
                ordered_paths.append(chart_path)
        for ref in results.get("references", []):
            if not isinstance(ref, dict):
                continue
            chart_key = ref.get("chartIdentityKey")
            chart_path = ref.get("chartImagePath")
            if not isinstance(chart_key, str) or not isinstance(chart_path, str):
                continue
            if chart_key in seen:
                continue
            seen.add(chart_key)
            ordered_paths.append(chart_path)
        return ordered_paths

    if results:
        ordered_paths: list[str] = []
        seen: set[str] = set()
        for ref in results.get("references", []):
            if not isinstance(ref, dict):
                continue
            chart_key = ref.get("chartIdentityKey")
            chart_path = ref.get("chartImagePath")
            if not isinstance(chart_key, str) or not isinstance(chart_path, str):
                continue
            if chart_key in seen:
                continue
            seen.add(chart_key)
            ordered_paths.append(chart_path)
        return ordered_paths

    return []


def sort_asset_records(
    library_root: Path,
    asset_records: list[AssetRecord],
) -> list[AssetRecord]:
    by_sample: dict[str, dict[str, AssetRecord]] = {}
    for record in asset_records:
        if record.sample_key:
            by_sample.setdefault(record.sample_key, {})[record.source_relpath] = record

    ordered: list[AssetRecord] = []
    seen_keys: set[str] = set()
    seen_paths: set[str] = set()

    sample_keys = sorted(by_sample.keys(), key=natural_key)
    for sample_key in sample_keys:
        ordered_paths = ordered_chart_paths_for_sample(library_root, sample_key)
        if not ordered_paths:
            continue
        for chart_path in ordered_paths:
            record = by_sample.get(sample_key, {}).get(chart_path)
            if record is None:
                continue
            if record.asset_key in seen_keys or record.source_relpath in seen_paths:
                continue
            seen_keys.add(record.asset_key)
            seen_paths.add(record.source_relpath)
            ordered.append(record)

    remaining = [record for record in asset_records if record.asset_key not in seen_keys]
    remaining.sort(key=lambda record: natural_key(Path(record.source_relpath).stem))
    ordered.extend(remaining)
    return ordered


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
    asset_records = sort_asset_records(library_root, asset_records)
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
