from __future__ import annotations

from pathlib import Path
from typing import Any

from .chart_assets import AssetRecord, summarize_thresholds
from .common import gather_string_list, read_json, unique_names


def default_new_sample_schema_path() -> Path:
    root = Path(__file__).resolve().parents[2]
    bundled = root / "config" / "new_sample_form_schema.json"
    if bundled.exists():
        return bundled
    return root / "Sources" / "SpinLabApp" / "config" / "new_sample_form_schema.json"


NEW_SAMPLE_SCHEMA_PATH = default_new_sample_schema_path()


def default_rules_book_dir() -> Path:
    settings = Path.home() / "Library" / "Application Support" / "SpinLab" / "rules_book.json"
    try:
        return Path(read_json(settings)["rulesBookPath"]).expanduser()
    except (OSError, KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"Cannot find the Rules Book location ({settings}): {error}") from error


def _normalize_substrate_token(token: Any) -> str:
    """Same normalisation as `FilenameRuleSet.normalizeForSubstrate` in the app."""
    text = str(token or "").upper()
    for ch in (" ", "_", "-", "(", ")", "（", "）"):
        text = text.replace(ch, "")
    return text


def default_substrate_treatment(treatments: list[dict[str, Any]], names: list[str]) -> str:
    """The treatment used when none is picked: the Rules Book's "original / untreated" entry.

    Mirrors `NativeSampleSubstrateChoices` in the app (an entry whose display name or any match value
    normalises to "O"; otherwise a treatment named "o"; otherwise "o"), so the phone page and the
    desktop window show the same default."""
    for entry in treatments:
        name = entry.get("displayName")
        if not isinstance(name, str) or name not in names:
            continue
        values = [name] + [m.get("value") for m in entry.get("matches", []) if isinstance(m, dict)]
        if any(_normalize_substrate_token(v) == "O" for v in values):
            return name
    return next((n for n in names if n.lower() == "o"), "o")


def batch_prefix_entries(rules_book_dir: Path) -> list[dict[str, Any]]:
    """The sample-identification entries that can name a batch prefix; malformed shapes are skipped, not fatal."""
    sample_id = read_json(rules_book_dir / "sample_identification.json").get("sampleId", {})
    matches = sample_id.get("matches", []) if isinstance(sample_id, dict) else []
    return [m for m in matches if isinstance(m, dict)]


def build_new_sample_form(rules_book_dir: Path, schema_path: Path | None = None) -> dict[str, Any]:
    """Options for the phone New Sample page, read from the Rules Book (the only copy of these lists)."""
    registry = read_json(rules_book_dir / "library_import_rules.json").get("registry", {})
    substrate = read_json(rules_book_dir / "sample_identification.json").get("substrate", {})

    def display_names(key: str) -> list[str]:
        return unique_names(entry.get("displayName") for entry in substrate.get(key, []))

    schema = read_json(schema_path or NEW_SAMPLE_SCHEMA_PATH)
    form = {
        "version": 1,
        # Field names, units and required fields: SpinLab's one New Sample definition, shared with the desktop window.
        "required": schema["required"],
        "numberFields": schema["numberFields"],
        "rheedFields": schema["rheedFields"],
        # Batch prefixes: the Rules Book's sample-identification "starts with" entries, the only list of them.
        "batchPrefixes": unique_names(
            str(m.get("value", "")).strip().upper()
            for m in batch_prefix_entries(rules_book_dir)
            if m.get("type") == "starts-with"
        ),
        "labs": unique_names(registry.get("labOptions", [])),
        "growthMaterials": unique_names(registry.get("growthMaterialOptions", [])),
        "substrate": {
            "treatments": display_names("treatments"),
            "defaultTreatment": default_substrate_treatment(
                substrate.get("treatments", []), display_names("treatments")
            ),
            "materials": display_names("materials"),
            "orientations": display_names("orientations"),
        },
    }
    missing = [
        name
        for name, values in [
            ("lab options", form["labs"]),
            ("growth material options", form["growthMaterials"]),
            ("substrate materials", form["substrate"]["materials"]),
            ("substrate orientations", form["substrate"]["orientations"]),
        ]
        if not values
    ]
    if missing:
        raise RuntimeError(
            f"Rules Book at {rules_book_dir} has no {', '.join(missing)}. "
            "Open SpinLab once so it fills in the new options, then export again."
        )
    return form


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
    substrates = gather_string_list(
        sample.get("substrateDisplay") or sample.get("substrateRaw")
        for sample in samples
        if sample.get("substrateDisplay") or sample.get("substrateRaw")
    )
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
