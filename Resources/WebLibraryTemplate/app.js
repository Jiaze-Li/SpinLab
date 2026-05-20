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

function formatUtcTimestamp(value) {
  if (!value) {
    return "";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())} UTC`;
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

function isEmptyMetadataValue(value) {
  if (value == null) {
    return true;
  }
  if (typeof value === "string") {
    return value.trim().length === 0;
  }
  if (Array.isArray(value)) {
    return value.length === 0;
  }
  if (typeof value === "object") {
    return Object.keys(value).length === 0;
  }
  return false;
}

function renderMetadata(sample) {
  const ordered = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata
    : Object.entries(sample.metadata ?? {}).map(([key, value]) => ({ key, value }));
  const numericEntries = Object.entries(sample.numericDisplay ?? {});
  const additionalMetadata = ordered.filter(
    (item) => !isDuplicateMetadataKey(item.key) && !isEmptyMetadataValue(item.value),
  );
  return `
    <div class="detail-section">
      <div class="section-title">Overview</div>
      ${renderFactList([
        ["Updated", formatUtcTimestamp(sample.updatedAt)],
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
