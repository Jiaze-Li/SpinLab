from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

from .common import natural_key, read_json, safe_slug, short_hash

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"}

WARN_CHART_BYTES = 200 * 1024 * 1024
FAIL_CHART_BYTES = 500 * 1024 * 1024
WARN_IMAGE_BYTES = 5 * 1024 * 1024
FAIL_IMAGE_BYTES = 20 * 1024 * 1024
WARN_IMAGE_COUNT = 2000
FAIL_IMAGE_COUNT = 5000

TAB_RANK = {
    "fieldSweep1omega": 0,
    "fieldSweep3omega": 1,
    "rahe1omegaVsT": 2,
    "rahe3omegaVsT": 3,
    "hcVsT": 4,
    "rtCurve": 5,
    "scaling": 6,
}


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


@dataclass(frozen=True)
class ActiveChartSource:
    chart_identity_key: str
    sample_key: str | None
    source_file: str
    source_relpath: str
    source_path: Path


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
    for ref in selected_refs:
        angle = extract_angle_value(
            ref.get("chartImagePath"),
            Path(str(ref.get("chartImagePath") or "")).stem,
            ref.get("source_file"),
        )
        if angle is not None:
            return angle
    return None


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


def collect_active_chart_sources(library_root: Path) -> tuple[list[ActiveChartSource], list[dict[str, Any]]]:
    sources: list[ActiveChartSource] = []
    warnings: list[dict[str, Any]] = []
    samples_root = library_root / "samples"
    if not samples_root.exists():
        return sources, warnings

    seen_keys: set[str] = set()
    seen_paths: set[str] = set()

    for sample_dir in sorted((path for path in samples_root.iterdir() if path.is_dir()), key=lambda path: natural_key(path.name)):
        sample_key = sample_dir.name
        results, _ = load_sample_indexes(library_root, sample_key)
        if not results:
            continue

        refs_by_path = {
            ref.get("chartImagePath"): ref
            for ref in results.get("references", [])
            if isinstance(ref, dict) and isinstance(ref.get("chartImagePath"), str)
        }
        ordered_paths = ordered_chart_paths_for_sample(library_root, sample_key)

        for chart_path in ordered_paths:
            ref = refs_by_path.get(chart_path)
            if not isinstance(ref, dict):
                continue
            chart_key = ref.get("chartIdentityKey")
            if not isinstance(chart_key, str):
                continue
            if chart_key in seen_keys or chart_path in seen_paths:
                continue

            seen_keys.add(chart_key)
            seen_paths.add(chart_path)

            source_path = library_root / chart_path
            if not source_path.exists():
                warnings.append(
                    {
                        "code": "missing_active_chart_png",
                        "message": "Active chart reference points to a missing PNG.",
                        "sample_key": sample_key,
                        "chart_identity_key": chart_key,
                        "chart_image_path": chart_path,
                    }
                )
                continue

            sources.append(
                ActiveChartSource(
                    chart_identity_key=chart_key,
                    sample_key=infer_sample_key(library_root, source_path) or sample_key,
                    source_file=source_path.name,
                    source_relpath=chart_path,
                    source_path=source_path,
                )
            )

    return sources, warnings


def build_asset_records(library_root: Path, output_dir: Path, sources: Iterable[ActiveChartSource]) -> list[AssetRecord]:
    records: list[AssetRecord] = []
    assets_dir = output_dir / "assets"
    for source in sources:
        rel_text = source.source_relpath
        digest = short_hash(rel_text)
        ext = source.source_path.suffix.lower()
        file_name = f"{safe_slug(source.sample_key or 'orphan')}--{digest}{ext}"
        destination_path = assets_dir / file_name
        asset_key = f"{source.sample_key or 'orphan'}::{source.source_file}::{digest}"
        url = f"assets/{quote(file_name)}"
        records.append(
            AssetRecord(
                asset_key=asset_key,
                url=url,
                sample_key=source.sample_key,
                source_file=source.source_file,
                size_bytes=source.source_path.stat().st_size,
                source_relpath=rel_text,
                source_path=source.source_path,
                destination_path=destination_path,
            )
        )
    return records


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
