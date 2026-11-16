#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path
from typing import Any

from web_library_export import (
    FAIL_CHART_BYTES,
    FAIL_IMAGE_BYTES,
    FAIL_IMAGE_COUNT,
    IMAGE_EXTENSIONS,
    NEW_SAMPLE_SCHEMA_PATH,
    RETIRED_WEB_TEMPLATE_FILES,
    TAB_RANK,
    WARN_CHART_BYTES,
    WARN_IMAGE_BYTES,
    WARN_IMAGE_COUNT,
    WEB_TEMPLATE_FILES,
    ActiveChartSource,
    AssetRecord,
    _normalize_substrate_token,
    batch_prefix_entries,
    build_asset_records,
    build_library_export,
    build_new_sample_form,
    build_report,
    build_warnings_and_errors,
    chart_sort_key,
    clean_generated_output,
    collect_active_chart_sources,
    default_new_sample_schema_path,
    default_rules_book_dir,
    default_substrate_treatment,
    ensure_inside,
    extract_angle_value,
    gather_string_list,
    group_angle_for_measurement,
    infer_sample_key,
    load_sample_indexes,
    measurement_group_angle,
    natural_key,
    ordered_chart_paths_for_sample,
    read_json,
    read_web_library_template,
    render_web_template,
    resolved_tab_key,
    safe_slug,
    short_hash,
    sort_asset_records,
    summarize_thresholds,
    unique_names,
    utc_now_iso,
    web_asset_version,
    web_library_template_dir,
    write_json,
    write_web_library_templates,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export SpinLab library data to a static web bundle.")
    parser.add_argument("--library-root", required=True, help="Root directory containing index/ and samples/")
    parser.add_argument("--output-dir", required=True, help="Destination directory for the static export")
    parser.add_argument("--force", action="store_true", help="Allow export to continue past hard asset thresholds")
    parser.add_argument(
        "--rules-book-dir",
        help="Rules Book directory (default: the one SpinLab is configured to use); source of the New Sample form options",
    )
    parser.add_argument(
        "--template-dir",
        help="Web Library template directory (default: bundled WebLibraryTemplate/ or Resources/WebLibraryTemplate/)",
    )
    parser.add_argument(
        "--schema-path",
        help="Path to new_sample_form_schema.json (default: bundled config/new_sample_form_schema.json)",
    )
    return parser.parse_args()


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

    # The phone form options come from the Rules Book. Read them before anything in the output
    # folder is touched, so a missing or empty Rules Book leaves the previous export intact.
    try:
        rules_book_dir = Path(args.rules_book_dir).expanduser() if args.rules_book_dir else default_rules_book_dir()
        schema_path = Path(args.schema_path).expanduser().resolve() if args.schema_path else None
        template_dir = web_library_template_dir(args.template_dir)
        new_sample_form = build_new_sample_form(rules_book_dir, schema_path=schema_path)
    except (RuntimeError, OSError, ValueError) as error:
        print(f"[spinlab-export] cannot build the new sample form: {error}", file=sys.stderr)
        return 2

    index = read_json(index_path)
    active_sources, active_warnings = collect_active_chart_sources(library_root)
    asset_records = build_asset_records(library_root, output_dir, active_sources)
    asset_records = sort_asset_records(library_root, asset_records)
    warnings, errors = build_warnings_and_errors(asset_records)
    warnings = active_warnings + warnings
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
    write_json(output_dir / "data" / "new_sample_form.json", new_sample_form)
    write_json(report_path, report)
    write_web_library_templates(output_dir, template_dir=template_dir)

    print_summary(output_dir, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
