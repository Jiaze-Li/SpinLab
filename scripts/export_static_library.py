#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
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


def render_index_html() -> str:
    return """<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="color-scheme" content="dark light" />
    <title>SpinLab Library</title>
    <link rel="stylesheet" href="./styles.css" />
  </head>
  <body>
    <div class="app-shell">
      <header class="topbar">
        <div>
          <div class="kicker">SpinLab web library export</div>
          <div class="title-row">
            <h1>Library</h1>
            <div id="title-badges" class="title-badges" aria-label="library metadata badges"></div>
          </div>
        </div>
        <div id="status" class="status">Loading data...</div>
      </header>

      <section class="summary-strip" id="summary-strip" aria-label="export summary"></section>

      <section class="controls" aria-label="filters">
        <label>
          <span>Search</span>
          <input id="search" type="search" placeholder="Sample, batch, substrate, metadata..." autocomplete="off" />
        </label>
        <label>
          <span>Batch</span>
          <select id="batch-filter"></select>
        </label>
        <label>
          <span>Sheet</span>
          <select id="sheet-filter"></select>
        </label>
        <label>
          <span>Asset group</span>
          <select id="asset-filter"></select>
        </label>
        <label class="toggle">
          <input id="chart-only" type="checkbox" />
          <span>Has charts</span>
        </label>
      </section>

      <main class="workspace">
        <section class="panel table-panel" aria-label="sample table">
          <div class="panel-head">
            <h2>Samples</h2>
            <div id="table-count" class="muted"></div>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Sample</th>
                  <th>Batch</th>
                  <th>Substrate</th>
                  <th class="num">Charts</th>
                  <th>Updated</th>
                </tr>
              </thead>
              <tbody id="sample-table"></tbody>
            </table>
          </div>
        </section>

        <aside class="panel detail-panel" aria-label="sample detail">
          <div class="panel-head detail-panel-head">
            <div class="kicker">Detail</div>
            <div id="detail-hint" class="muted"></div>
          </div>
          <div id="detail-body" class="detail-body"></div>
        </aside>
      </main>

      <section class="panel report-panel" aria-label="export report">
        <div class="panel-head">
          <h2>Export report</h2>
          <div id="report-status" class="muted"></div>
        </div>
        <div id="report-body" class="report-body"></div>
      </section>
    </div>
    <script src="./app.js" defer></script>
  </body>
</html>
"""


def render_styles_css() -> str:
    return """\
:root {
  color-scheme: light dark;
  --bg: #f5f7fb;
  --bg-accent: #eef3ff;
  --surface: #ffffff;
  --surface-soft: #f6f8fc;
  --line: rgba(31, 41, 55, 0.10);
  --line-strong: rgba(31, 41, 55, 0.14);
  --text: #1f2937;
  --muted: #6b7280;
  --accent: #2563eb;
  --accent-soft: rgba(37, 99, 235, 0.10);
  --accent-line: rgba(37, 99, 235, 0.18);
  --warn: #b45309;
  --error: #b91c1c;
  --ok: #15803d;
  --radius: 12px;
  --radius-sm: 9px;
  --shadow: 0 1px 2px rgba(15, 23, 42, 0.04), 0 10px 24px rgba(15, 23, 42, 0.05);
  --shadow-soft: 0 1px 1px rgba(15, 23, 42, 0.03);
  --table-head-bg: rgba(246, 248, 252, 0.96);
  --chart-bg: #eef2f7;
  --row-hover: rgba(37, 99, 235, 0.05);
  --row-selected: rgba(37, 99, 235, 0.09);
}

@media (prefers-color-scheme: dark) {
  :root {
    color-scheme: dark;
    --bg: #0b1020;
    --bg-accent: #11192e;
    --surface: #121826;
    --surface-soft: #0f1521;
    --line: rgba(148, 163, 184, 0.14);
    --line-strong: rgba(148, 163, 184, 0.22);
    --text: #e5e7eb;
    --muted: #9ca3af;
    --accent: #60a5fa;
    --accent-soft: rgba(96, 165, 250, 0.14);
    --accent-line: rgba(96, 165, 250, 0.22);
    --warn: #f59e0b;
    --error: #f87171;
    --ok: #4ade80;
    --shadow: 0 1px 2px rgba(0, 0, 0, 0.20), 0 14px 28px rgba(0, 0, 0, 0.22);
    --shadow-soft: 0 1px 1px rgba(0, 0, 0, 0.18);
    --table-head-bg: rgba(17, 25, 46, 0.96);
    --chart-bg: #0b1220;
    --row-hover: rgba(96, 165, 250, 0.08);
    --row-selected: rgba(96, 165, 250, 0.14);
  }
}

* {
  box-sizing: border-box;
}

html,
body {
  margin: 0;
  min-height: 100%;
  background:
    radial-gradient(1200px 800px at 10% 0%, var(--bg-accent), transparent 52%),
    radial-gradient(900px 700px at 100% 0%, rgba(59, 130, 246, 0.08), transparent 42%),
    var(--bg);
  color: var(--text);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 13.5px;
  line-height: 1.45;
}

body {
  padding: 18px;
}

.app-shell {
  display: grid;
  gap: 14px;
}

.topbar,
.panel,
.controls,
.summary-strip {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--surface);
  box-shadow: var(--shadow);
}

.topbar {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: center;
  padding: 2px 6px 12px;
  border: 0;
  border-bottom: 1px solid var(--line);
  border-radius: 0;
  background: transparent;
  box-shadow: none;
}

.kicker {
  color: var(--muted);
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0;
}

.title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.title-badges {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

h1,
h2,
h3,
p {
  margin: 0;
}

h1 {
  font-size: 21px;
  font-weight: 680;
  letter-spacing: -0.02em;
}

h2 {
  font-size: 14px;
  font-weight: 650;
  letter-spacing: -0.01em;
}

.status,
.muted {
  color: var(--muted);
}

.summary-strip {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 10px;
  padding: 0;
  border: 0;
  background: transparent;
  box-shadow: none;
}

.metric {
  border: 1px solid var(--line);
  border-radius: calc(var(--radius) - 2px);
  background: linear-gradient(180deg, var(--surface), var(--surface-soft));
  padding: 11px 12px;
  box-shadow: var(--shadow-soft);
}

.metric .label {
  color: var(--muted);
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.metric .value {
  font-size: 17px;
  font-weight: 670;
  letter-spacing: -0.01em;
  margin-top: 4px;
}

.badge {
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 4px 9px;
  font-size: 10.5px;
  line-height: 1.2;
  white-space: nowrap;
  background: rgba(127, 140, 160, 0.08);
}

.badge-subtle {
  color: var(--muted);
}

.badge-warn {
  border-color: rgba(245, 158, 11, 0.34);
  background: rgba(245, 158, 11, 0.12);
  color: var(--warn);
}

.badge-error {
  border-color: rgba(239, 68, 68, 0.34);
  background: rgba(239, 68, 68, 0.12);
  color: var(--error);
}

.controls {
  display: grid;
  grid-template-columns: minmax(220px, 2fr) repeat(3, minmax(160px, 1fr)) auto;
  gap: 10px 12px;
  padding: 12px;
  align-items: end;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.65), var(--surface));
}

.controls label {
  display: grid;
  gap: 5px;
}

.controls span {
  color: var(--muted);
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.controls input[type="search"],
.controls select {
  width: 100%;
  min-height: 36px;
  border: 1px solid var(--line-strong);
  border-radius: calc(var(--radius) - 4px);
  background: var(--surface);
  color: var(--text);
  padding: 8px 10px;
  font: inherit;
  box-shadow: var(--shadow-soft);
}

.controls .toggle {
  display: flex;
  flex-direction: row;
  gap: 8px;
  align-items: center;
  padding-bottom: 6px;
  color: var(--text);
}

.controls .toggle input {
  margin: 0;
  accent-color: var(--accent);
}

.workspace {
  display: grid;
  grid-template-columns: minmax(620px, 1.35fr) minmax(340px, 0.9fr);
  gap: 14px;
  align-items: start;
}

.panel {
  padding: 13px;
  background: linear-gradient(180deg, var(--surface), rgba(255, 255, 255, 0.96));
}

.panel-head {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: baseline;
  margin-bottom: 10px;
}

.detail-panel-head {
  align-items: flex-start;
}

.table-wrap {
  overflow: auto;
  max-height: calc(100vh - 280px);
  border: 1px solid var(--line);
  border-radius: calc(var(--radius) - 2px);
  background: var(--surface);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
}

table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  background: transparent;
}

thead th {
  position: sticky;
  top: 0;
  background: var(--table-head-bg);
  backdrop-filter: blur(10px);
  z-index: 1;
  text-align: left;
  padding: 10px 12px;
  font-weight: 600;
  color: var(--muted);
  border-bottom: 1px solid var(--line);
}

tbody td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--line);
  vertical-align: top;
  background: transparent;
}

tbody tr:last-child td {
  border-bottom: 0;
}

tbody tr {
  cursor: pointer;
  transition: background-color 120ms ease, box-shadow 120ms ease;
}

tbody tr:hover {
  background: var(--row-hover);
}

tbody tr.selected {
  background: var(--row-selected);
}

tbody tr.selected td:first-child {
  box-shadow: inset 2px 0 0 var(--accent);
}

.num {
  text-align: right;
}

.detail-body,
.report-body {
  display: grid;
  gap: 14px;
}

.report-summary {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 10px;
  padding: 4px 0 2px;
}

.report-summary-line {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0;
  min-width: 0;
  color: var(--text);
  font-weight: 600;
}

.report-summary-line .separator {
  color: var(--muted);
  font-weight: 500;
  margin: 0 8px;
}

.report-details {
  border-top: 1px solid var(--line);
  padding-top: 10px;
}

.report-details summary {
  cursor: pointer;
  list-style: none;
  color: var(--muted);
  font-size: 11.5px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.report-details summary::-webkit-details-marker {
  display: none;
}

.report-details-body {
  display: grid;
  gap: 14px;
  padding-top: 12px;
}

.detail-summary {
  display: grid;
  gap: 1px;
}

.detail-title {
  color: var(--text);
  font-size: 18px;
  font-weight: 690;
  line-height: 1.15;
  letter-spacing: -0.02em;
}

.detail-subtitle {
  color: var(--muted);
  font-size: 11.5px;
}

.source-details {
  color: var(--muted);
  padding-top: 2px;
  border-top: 1px solid var(--line);
}

.source-details summary {
  cursor: pointer;
  font-size: 11.5px;
  list-style: none;
  color: var(--text);
  font-weight: 600;
}

.source-details summary::-webkit-details-marker {
  display: none;
}

.source-details-body {
  margin-top: 10px;
}

.kv-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px 14px;
}

.kv {
  min-width: 0;
  padding: 10px 0;
  border-bottom: 1px solid var(--line);
}

.kv .label {
  color: var(--muted);
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.kv .value {
  margin-top: 4px;
  font-size: 13px;
  word-break: break-word;
}

.kv-grid > .kv:last-child {
  border-bottom: 0;
}

.kv-grid > .kv:nth-last-child(2):nth-child(odd) {
  border-bottom: 0;
}

.detail-section {
  display: grid;
  gap: 8px;
}

.fact-list {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0 16px;
  border-top: 1px solid var(--line);
}

.fact {
  min-width: 0;
  padding: 10px 0;
  border-bottom: 1px solid var(--line);
}

.fact .label {
  color: var(--muted);
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.fact .value {
  margin-top: 4px;
  font-size: 13px;
  word-break: break-word;
}

.fact-list > .fact:last-child {
  border-bottom: 0;
}

.tag-row {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.chip {
  border: 1px solid var(--line);
  border-radius: 999px;
  background: var(--surface-soft);
  color: var(--text);
  padding: 4px 8px;
  font-size: 12px;
}

.chip.warn {
  border-color: rgba(245, 158, 11, 0.4);
  color: var(--warn);
}

.chip.error {
  border-color: rgba(239, 68, 68, 0.4);
  color: var(--error);
}

.chip.ok {
  border-color: rgba(34, 197, 94, 0.4);
  color: var(--ok);
}

.chart-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 10px;
}

.chart {
  border: 1px solid var(--line);
  border-radius: calc(var(--radius) - 2px);
  background: linear-gradient(180deg, var(--surface), var(--surface-soft));
  padding: 8px;
  box-shadow: var(--shadow-soft);
}

.chart img {
  display: block;
  width: 100%;
  height: 120px;
  object-fit: cover;
  border-radius: 4px;
  background: var(--chart-bg);
}

.chart .caption {
  margin-top: 6px;
  color: var(--muted);
  font-size: 12px;
  word-break: break-word;
}

.section-title {
  margin-bottom: 8px;
  font-weight: 650;
  color: var(--text);
}

.warning-list,
.error-list {
  display: grid;
  gap: 6px;
}

.warning,
.error {
  border: 1px solid var(--line);
  border-radius: calc(var(--radius) - 2px);
  background: var(--surface-soft);
  padding: 8px 10px;
}

.warning {
  border-color: rgba(245, 158, 11, 0.35);
}

.error {
  border-color: rgba(239, 68, 68, 0.35);
}

@media (max-width: 1100px) {
  .summary-strip {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .controls {
    grid-template-columns: 1fr 1fr;
  }

  .workspace {
    grid-template-columns: 1fr;
  }

  .table-wrap {
    max-height: none;
  }
}

@media (max-width: 700px) {
  body {
    padding: 10px;
  }

  .topbar {
    flex-direction: column;
    align-items: flex-start;
  }

  .summary-strip,
  .controls,
  .kv-grid {
    grid-template-columns: 1fr;
  }

  .fact-list {
    grid-template-columns: 1fr;
  }
}
"""


def render_app_js() -> str:
    return """\
const state = {
  library: null,
  report: null,
  selectedKey: null,
  filters: {
    search: "",
    batch: "all",
    sheet: "all",
    assetGroup: "all",
    chartsOnly: false,
  },
};

const els = {};

function byId(id) {
  return document.getElementById(id);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function formatBytes(bytes) {
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function sampleCharts(sampleKey) {
  return (state.report?.assetStats?.assets ?? []).filter((asset) => asset.sample_key === sampleKey);
}

function normaliseText(value) {
  return String(value ?? "").toLowerCase();
}

function sampleMatches(sample) {
  const search = state.filters.search.trim().toLowerCase();
  if (state.filters.batch !== "all" && sample.batchId !== state.filters.batch) {
    return false;
  }
  if (state.filters.sheet !== "all" && (sample.sourceSheetName ?? "") !== state.filters.sheet) {
    return false;
  }
  if (state.filters.assetGroup !== "all" && !sampleCharts(sample.id).some((asset) => asset.sample_key === state.filters.assetGroup)) {
    return false;
  }
  if (state.filters.chartsOnly && sampleCharts(sample.id).length === 0) {
    return false;
  }
  if (!search) {
    return true;
  }
  const haystack = [
    sample.id,
    sample.displayName,
    sample.batchId,
    sample.substrateRaw,
    sample.substrateDisplay,
    sample.sourceSheetName,
    JSON.stringify(sample.metadata ?? {}),
    JSON.stringify(sample.numericDisplay ?? {}),
    JSON.stringify(sample.numericTags ?? {}),
    JSON.stringify(sample.substrateTags ?? []),
  ]
    .map(normaliseText)
    .join(" | ");
  return haystack.includes(search);
}

function filteredSamples() {
  return (state.library?.samples ?? []).filter(sampleMatches);
}

function assetGroupLabel(sampleKey) {
  if (!sampleKey) {
    return "Orphan charts";
  }
  if (sampleKey === "multi-sample") {
    return "Multi-sample charts";
  }
  return sampleKey;
}

function renderSummaryStrip() {
  const summary = state.library?.sourceSummary ?? {};
  const report = state.report ?? {};
  const assetStats = report.assetStats ?? {};
  const values = [
    ["Batches", summary.batchCount ?? 0],
    ["Samples", summary.sampleCount ?? 0],
    ["Charts", assetStats.chartCount ?? 0],
    ["Chart size", formatBytes(assetStats.chartBytes ?? 0)],
  ];
  els.summaryStrip.innerHTML = values
    .map(([label, value]) => `
      <div class="metric">
        <div class="label">${escapeHtml(label)}</div>
        <div class="value">${escapeHtml(value)}</div>
      </div>
    `)
    .join("");
}

function renderTitleBadges() {
  const schemaVersion = state.library?.schemaVersion;
  const badges = [
    schemaVersion != null ? `<span class="badge badge-subtle">Schema v${escapeHtml(schemaVersion)}</span>` : "",
    state.report?.forced ? `<span class="badge badge-warn">Forced export</span>` : "",
  ].filter(Boolean);
  els.titleBadges.innerHTML = badges.join("");
}

function populateFilters() {
  const library = state.library;
  if (!library) {
    return;
  }

  const batches = ["all", ...(library.filters?.batchIds ?? [])];
  const sheets = ["all", ...(library.filters?.sheetNames ?? [])];
  const sampleIds = new Set((library.samples ?? []).map((sample) => sample.id));
  const assetGroups = ["all", ...((state.report?.assetStats?.sampleKeys ?? []).filter((value) => sampleIds.has(value)))];

  els.batchFilter.innerHTML = batches
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All batches" : value)}</option>`)
    .join("");
  els.sheetFilter.innerHTML = sheets
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All sheets" : value)}</option>`)
    .join("");
  els.assetFilter.innerHTML = assetGroups
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All asset groups" : assetGroupLabel(value))}</option>`)
    .join("");
}

function renderTable() {
  const samples = filteredSamples();
  els.tableCount.textContent = `${samples.length} of ${state.library?.samples?.length ?? 0}`;
  els.sampleTable.innerHTML = samples
    .map((sample) => {
      const chartCount = sampleCharts(sample.id).length;
      const selected = sample.id === state.selectedKey ? "selected" : "";
      return `
        <tr class="${selected}" data-sample-key="${escapeHtml(sample.id)}">
          <td>
            <div>${escapeHtml(sample.displayName)}</div>
            <div class="muted">${escapeHtml(sample.id)}</div>
          </td>
          <td>${escapeHtml(sample.batchId)}</td>
          <td>${escapeHtml(sample.substrateDisplay || sample.substrateRaw || "")}</td>
          <td class="num">${escapeHtml(chartCount)}</td>
          <td>${escapeHtml((sample.updatedAt ?? "").slice(0, 10))}</td>
        </tr>
      `;
    })
    .join("");

  Array.from(els.sampleTable.querySelectorAll("tr[data-sample-key]")).forEach((row) => {
    row.addEventListener("click", () => selectSample(row.dataset.sampleKey));
  });
}

function renderKeyValueGrid(entries) {
  return `
    <div class="kv-grid">
      ${entries
        .map(
          ([label, value]) => `
            <div class="kv">
              <div class="label">${escapeHtml(label)}</div>
              <div class="value">${escapeHtml(value)}</div>
            </div>
          `,
        )
        .join("")}
    </div>
  `;
}

function renderFactList(entries) {
  return `
    <div class="fact-list">
      ${entries
        .map(
          ([label, value]) => `
            <div class="fact">
              <div class="label">${escapeHtml(label)}</div>
              <div class="value">${escapeHtml(value)}</div>
            </div>
          `,
        )
        .join("")}
    </div>
  `;
}

function normalizeMetadataKey(key) {
  return String(key ?? "").trim().toLowerCase();
}

function isDuplicateMetadataKey(key) {
  return new Set([
    "编号",
    "sample",
    "batch",
    "substrate",
    "生长温度",
    "温度",
    "氧压",
    "能量",
    "厚度",
  ]).has(normalizeMetadataKey(key));
}

function renderMetadata(sample) {
  const ordered = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata
    : Object.entries(sample.metadata ?? {}).map(([key, value]) => ({ key, value }));
  const numericEntries = Object.entries(sample.numericDisplay ?? {});
  const additionalMetadata = ordered.filter((item) => !isDuplicateMetadataKey(item.key));
  return `
    <div class="detail-section">
      <div class="section-title">Overview</div>
      ${renderFactList([
        ["Batch", sample.batchId],
        ["Substrate", sample.substrateDisplay || sample.substrateRaw || ""],
        ["Updated", sample.updatedAt ?? ""],
        ["Charts", sampleCharts(sample.id).length],
      ])}
    </div>
    <details class="source-details">
      <summary>Sheet and row provenance</summary>
      <div class="source-details-body">
        ${renderFactList([
          ["Sheet", sample.sourceSheetName ?? ""],
          ["Row", sample.sourceRowNumber ?? ""],
        ])}
      </div>
    </details>
    <div class="detail-section">
      <div class="section-title">Numeric tags</div>
      <div class="tag-row">
        ${numericEntries.length
          ? numericEntries
              .map(
                ([label, value]) => `
                  <span class="chip">${escapeHtml(label)}: ${escapeHtml(value)}</span>
                `,
              )
              .join("")
          : `<div class="muted">None</div>`}
      </div>
    </div>
    ${additionalMetadata.length
      ? `
        <div class="detail-section">
          <div class="section-title">Additional metadata</div>
          <div class="kv-grid">
            ${additionalMetadata
              .map(
                (item) => `
                  <div class="kv">
                    <div class="label">${escapeHtml(item.key)}</div>
                    <div class="value">${escapeHtml(item.value ?? "")}</div>
                  </div>
                `,
              )
              .join("")}
          </div>
        </div>
      `
      : ""}
  `;
}

function renderCharts(sample) {
  const charts = sampleCharts(sample.id);
  if (charts.length === 0) {
    return `
      <div class="section-title">Charts</div>
      <div class="muted">No chart images were exported for this sample.</div>
    `;
  }
  return `
    <div class="section-title">Charts</div>
    <div class="chart-grid">
      ${charts
        .map(
          (chart) => `
            <div class="chart">
              <img loading="lazy" src="${escapeHtml(chart.url)}" alt="${escapeHtml(chart.asset_key)}" />
              <div class="caption">${escapeHtml(chart.source_file)}<br />${escapeHtml(formatBytes(chart.size_bytes))}</div>
            </div>
          `,
        )
        .join("")}
    </div>
  `;
}

function renderDetail() {
  const sample = (state.library?.samples ?? []).find((item) => item.id === state.selectedKey);
  if (!sample) {
    els.detailHint.textContent = "Select a sample row";
    els.detailBody.innerHTML = `<div class="muted">No sample selected.</div>`;
    return;
  }
  els.detailHint.innerHTML = `
    <div class="detail-summary">
      <div class="detail-title">${escapeHtml(sample.displayName)}</div>
      <div class="detail-subtitle">Sample ID: ${escapeHtml(sample.id)}</div>
    </div>
  `;
  els.detailBody.innerHTML = `
    ${renderMetadata(sample)}
    ${renderCharts(sample)}
  `;
}

function renderReport() {
  const report = state.report ?? {};
  els.reportStatus.textContent = "";
  const warnings = report.warnings ?? [];
  const errors = report.errors ?? [];
  const assetStats = report.assetStats ?? {};
  const thresholds = report.thresholds ?? {};
  const assets = assetStats.assets ?? [];
  const sampleKeys = Array.from(new Set(assets.map((asset) => asset.sample_key).filter(Boolean)));
  const summaryParts = [
    errors.length > 0 ? "Export issues" : "Export OK",
    `${assetStats.chartCount ?? 0} charts`,
    formatBytes(assetStats.chartBytes ?? 0),
  ];
  const badges = [
    warnings.length ? `<span class="badge badge-warn">Warnings ${escapeHtml(warnings.length)}</span>` : "",
    errors.length ? `<span class="badge badge-error">Errors ${escapeHtml(errors.length)}</span>` : "",
  ].filter(Boolean);

  els.reportBody.innerHTML = `
    <div class="report-summary" aria-label="export report summary">
      <div class="report-summary-line">
        ${summaryParts
          .map((part, index) =>
            index === 0
              ? `<span>${escapeHtml(part)}</span>`
              : `<span class="separator">·</span><span>${escapeHtml(part)}</span>`,
          )
          .join("")}
      </div>
      ${badges.join("")}
    </div>
    <details class="report-details">
      <summary>Report details</summary>
      <div class="report-details-body">
        ${renderKeyValueGrid([
          ["Exported at", report.exportedAt ?? ""],
          ["Largest asset", assetStats.largestChartKey ?? ""],
        ])}
        <div class="detail-section">
          <div class="section-title">Asset groups</div>
          <div class="chips">
            ${sampleKeys
              .map((value) => `<span class="chip">${escapeHtml(assetGroupLabel(value))}</span>`)
              .join("")}
          </div>
        </div>
        <div class="detail-section">
          <div class="section-title">Thresholds</div>
          ${renderKeyValueGrid(Object.entries(thresholds).map(([key, value]) => [key, value]))}
        </div>
        <div class="detail-section">
          <div class="section-title">Warnings</div>
          <div class="warning-list">
            ${
              warnings.length
                ? warnings
                    .map(
                      (warning) => `
                        <div class="warning">
                          <div><strong>${escapeHtml(warning.code)}</strong></div>
                          <div class="muted">${escapeHtml(warning.message)}</div>
                        </div>
                      `,
                    )
                    .join("")
                : `<div class="muted">None</div>`
            }
          </div>
        </div>
        <div class="detail-section">
          <div class="section-title">Errors</div>
          <div class="error-list">
            ${
              errors.length
                ? errors
                    .map(
                      (error) => `
                        <div class="error">
                          <div><strong>${escapeHtml(error.code)}</strong></div>
                          <div class="muted">${escapeHtml(error.message)}</div>
                        </div>
                      `,
                    )
                    .join("")
                : `<div class="muted">None</div>`
            }
          </div>
        </div>
      </div>
    </details>
  `;
}

function reRender() {
  renderSummaryStrip();
  renderTitleBadges();
  renderTable();
  renderDetail();
  renderReport();
  els.status.textContent = `${filteredSamples().length} samples visible`;
}

function selectSample(sampleKey) {
  state.selectedKey = sampleKey;
  renderTable();
  renderDetail();
}

function attachEvents() {
  els.search.addEventListener("input", (event) => {
    state.filters.search = event.target.value;
    renderTable();
    els.status.textContent = `${filteredSamples().length} samples visible`;
  });
  els.batchFilter.addEventListener("change", (event) => {
    state.filters.batch = event.target.value;
    renderTable();
    els.status.textContent = `${filteredSamples().length} samples visible`;
  });
  els.sheetFilter.addEventListener("change", (event) => {
    state.filters.sheet = event.target.value;
    renderTable();
    els.status.textContent = `${filteredSamples().length} samples visible`;
  });
  els.assetFilter.addEventListener("change", (event) => {
    state.filters.assetGroup = event.target.value;
    renderTable();
    els.status.textContent = `${filteredSamples().length} samples visible`;
  });
  els.chartOnly.addEventListener("change", (event) => {
    state.filters.chartsOnly = event.target.checked;
    renderTable();
    els.status.textContent = `${filteredSamples().length} samples visible`;
  });
}

async function loadData() {
  const [libraryResponse, reportResponse] = await Promise.all([
    fetch("./data/library.json"),
    fetch("./data/export_report.json"),
  ]);
  if (!libraryResponse.ok) {
    throw new Error(`Failed to load library.json (${libraryResponse.status})`);
  }
  if (!reportResponse.ok) {
    throw new Error(`Failed to load export_report.json (${reportResponse.status})`);
  }
  state.library = await libraryResponse.json();
  state.report = await reportResponse.json();
}

async function main() {
  els.status = byId("status");
  els.summaryStrip = byId("summary-strip");
  els.search = byId("search");
  els.batchFilter = byId("batch-filter");
  els.sheetFilter = byId("sheet-filter");
  els.assetFilter = byId("asset-filter");
  els.chartOnly = byId("chart-only");
  els.tableCount = byId("table-count");
  els.sampleTable = byId("sample-table");
  els.detailHint = byId("detail-hint");
  els.detailBody = byId("detail-body");
  els.titleBadges = byId("title-badges");
  els.reportStatus = byId("report-status");
  els.reportBody = byId("report-body");

  try {
    await loadData();
    state.selectedKey = state.library.samples[0]?.id ?? null;
    populateFilters();
    attachEvents();
    reRender();
  } catch (error) {
    els.status.textContent = "Load failed";
    els.detailBody.innerHTML = `<div class="error"><strong>Unable to load export data.</strong><div class="muted">${escapeHtml(error.message)}</div></div>`;
  }
}

main();
"""


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
    (output_dir / "index.html").write_text(render_index_html(), encoding="utf-8")
    (output_dir / "styles.css").write_text(render_styles_css(), encoding="utf-8")
    (output_dir / "app.js").write_text(render_app_js(), encoding="utf-8")

    print_summary(output_dir, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
