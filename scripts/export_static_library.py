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
  --bg: #f6f8fa;
  --surface: #ffffff;
  --surface-2: #f3f4f6;
  --line: #d0d7de;
  --text: #24292f;
  --muted: #57606a;
  --accent: #0969da;
  --accent-soft: rgba(9, 105, 218, 0.1);
  --warn: #9a6700;
  --error: #cf222e;
  --ok: #1a7f37;
  --radius: 6px;
  --shadow: 0 12px 32px rgba(0, 0, 0, 0.08);
  --panel-accent: var(--surface-2);
  --table-head-bg: #eaeef2;
  --chart-bg: #eaeef2;
}

@media (prefers-color-scheme: dark) {
  :root {
    color-scheme: dark;
    --bg: #0d1117;
    --surface: #161b22;
    --surface-2: #0f141b;
    --line: #30363d;
    --text: #e6edf3;
    --muted: #8b949e;
    --accent: #58a6ff;
    --accent-soft: rgba(88, 166, 255, 0.14);
    --warn: #d29922;
    --error: #f85149;
    --ok: #3fb950;
    --shadow: 0 12px 32px rgba(0, 0, 0, 0.22);
    --panel-accent: var(--surface);
    --table-head-bg: #11161d;
    --chart-bg: #0b0f14;
  }
}

* {
  box-sizing: border-box;
}

html,
body {
  margin: 0;
  min-height: 100%;
  background: var(--bg);
  color: var(--text);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 14px;
  line-height: 1.4;
}

body {
  padding: 16px;
}

.app-shell {
  display: grid;
  gap: 12px;
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
  padding: 14px 16px;
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
  font-size: 20px;
  font-weight: 650;
}

h2 {
  font-size: 15px;
  font-weight: 600;
}

.status,
.muted {
  color: var(--muted);
}

.summary-strip {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 8px;
  padding: 12px;
}

.metric {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--surface-2);
  padding: 10px 12px;
}

.metric .label {
  color: var(--muted);
  font-size: 12px;
}

.metric .value {
  font-size: 18px;
  font-weight: 650;
  margin-top: 4px;
}

.badge {
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 3px 8px;
  font-size: 11px;
  line-height: 1.2;
  white-space: nowrap;
}

.badge-subtle {
  background: rgba(139, 148, 158, 0.12);
  color: var(--muted);
}

.badge-warn {
  border-color: rgba(210, 153, 34, 0.45);
  background: rgba(210, 153, 34, 0.12);
  color: #f2cc60;
}

.controls {
  display: grid;
  grid-template-columns: minmax(220px, 2fr) repeat(3, minmax(160px, 1fr)) auto;
  gap: 10px;
  padding: 12px;
  align-items: end;
}

.controls label {
  display: grid;
  gap: 6px;
}

.controls span {
  color: var(--muted);
  font-size: 12px;
}

.controls input[type="search"],
.controls select {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--surface-2);
  color: var(--text);
  padding: 9px 10px;
  font: inherit;
}

.controls .toggle {
  display: flex;
  flex-direction: row;
  gap: 8px;
  align-items: center;
  padding-bottom: 7px;
}

.workspace {
  display: grid;
  grid-template-columns: minmax(620px, 1.35fr) minmax(340px, 0.9fr);
  gap: 12px;
  align-items: start;
}

.panel {
  padding: 12px;
}

.panel-head {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: baseline;
  margin-bottom: 12px;
}

.detail-panel-head {
  align-items: flex-start;
}

.table-wrap {
  overflow: auto;
  max-height: calc(100vh - 280px);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}

table {
  width: 100%;
  border-collapse: collapse;
  background: var(--surface-2);
}

thead th {
  position: sticky;
  top: 0;
  background: var(--table-head-bg);
  z-index: 1;
  text-align: left;
  padding: 10px 12px;
  font-weight: 600;
  color: var(--muted);
  border-bottom: 1px solid var(--line);
}

tbody td {
  padding: 9px 12px;
  border-bottom: 1px solid rgba(48, 54, 61, 0.7);
  vertical-align: top;
}

tbody tr {
  cursor: pointer;
}

tbody tr:hover {
  background: rgba(88, 166, 255, 0.08);
}

tbody tr.selected {
  background: var(--accent-soft);
}

.num {
  text-align: right;
}

.detail-body,
.report-body {
  display: grid;
  gap: 12px;
}

.detail-summary {
  display: grid;
  gap: 2px;
}

.detail-title {
  color: var(--text);
  font-size: 16px;
  font-weight: 650;
  line-height: 1.2;
}

.detail-subtitle {
  color: var(--muted);
  font-size: 12px;
}

.source-details {
  color: var(--muted);
}

.source-details summary {
  cursor: pointer;
  font-size: 12px;
  list-style: none;
}

.source-details summary::-webkit-details-marker {
  display: none;
}

.source-details-body {
  margin-top: 8px;
}

.kv-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}

.kv {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--surface-2);
  padding: 8px 10px;
}

.kv .label {
  color: var(--muted);
  font-size: 12px;
}

.kv .value {
  margin-top: 3px;
  word-break: break-word;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.chip {
  border: 1px solid var(--line);
  border-radius: 999px;
  background: var(--surface-2);
  color: var(--text);
  padding: 4px 8px;
  font-size: 12px;
}

.chip.warn {
  border-color: rgba(210, 153, 34, 0.6);
  color: #f2cc60;
}

.chip.error {
  border-color: rgba(248, 81, 73, 0.6);
  color: #ffa198;
}

.chip.ok {
  border-color: rgba(63, 185, 80, 0.6);
  color: #7ee787;
}

.chart-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 10px;
}

.chart {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--surface-2);
  padding: 8px;
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
  font-weight: 600;
}

.warning-list,
.error-list {
  display: grid;
  gap: 6px;
}

.warning,
.error {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--surface-2);
  padding: 8px 10px;
}

.warning {
  border-color: rgba(210, 153, 34, 0.5);
}

.error {
  border-color: rgba(248, 81, 73, 0.5);
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

function renderMetadata(sample) {
  const ordered = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata
    : Object.entries(sample.metadata ?? {}).map(([key, value]) => ({ key, value }));
  const numericEntries = Object.entries(sample.numericDisplay ?? {});
  return `
    <div class="section-title">Overview</div>
    ${renderKeyValueGrid([
      ["Batch", sample.batchId],
      ["Substrate", sample.substrateDisplay || sample.substrateRaw || ""],
      ["Updated", sample.updatedAt ?? ""],
      ["Charts", sampleCharts(sample.id).length],
    ])}
    <details class="source-details">
      <summary>Sheet and row provenance</summary>
      <div class="source-details-body">
        ${renderKeyValueGrid([
          ["Sheet", sample.sourceSheetName ?? ""],
          ["Row", sample.sourceRowNumber ?? ""],
        ])}
      </div>
    </details>
    <div class="section-title">Numeric tags</div>
    ${renderKeyValueGrid(numericEntries)}
    <div class="section-title">Ordered metadata</div>
    <div class="kv-grid">
      ${ordered
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

  els.reportBody.innerHTML = `
    ${renderKeyValueGrid([
      ["Exported at", report.exportedAt ?? ""],
      ["Chart assets", assetStats.chartCount ?? 0],
      ["Chart bytes", formatBytes(assetStats.chartBytes ?? 0)],
      ["Largest asset", assetStats.largestChartKey ?? ""],
    ])}
    <div class="section-title">Asset groups</div>
    <div class="chips">
      ${sampleKeys
        .map((value) => `<span class="chip">${escapeHtml(assetGroupLabel(value))}</span>`)
        .join("")}
    </div>
    <div class="section-title">Thresholds</div>
    ${renderKeyValueGrid(Object.entries(thresholds).map(([key, value]) => [key, value]))}
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
