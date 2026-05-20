const state = {
  library: null,
  report: null,
  selectedKey: null,
  filters: {
    search: "",
    series: "all",
    batch: "all",
    sheet: "all",
    assetGroup: "all",
    chartsOnly: false,
  },
};

const SERIES_FILTERS = [
  { value: "PN", label: "PN", prefixes: ["PN"] },
  { value: "SL", label: "SL", prefixes: ["SL"] },
];

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

function normalisePrefix(value) {
  return String(value ?? "").trim().toUpperCase();
}

function sampleSeriesHaystack(sample) {
  return [sample.batchId, sample.id, sample.displayName]
    .map(normalisePrefix)
    .filter(Boolean);
}

function sampleMatchesSeries(sample, series) {
  if (series === "all") {
    return true;
  }
  const family = SERIES_FILTERS.find((item) => item.value === series);
  if (!family) {
    return true;
  }
  const haystack = sampleSeriesHaystack(sample);
  return haystack.some((value) => family.prefixes.some((prefix) => value.startsWith(prefix)));
}

function sampleMatches(sample) {
  const search = state.filters.search.trim().toLowerCase();
  if (!sampleMatchesSeries(sample, state.filters.series)) {
    return false;
  }
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
  const warnings = state.report?.warnings ?? [];
  const errors = state.report?.errors ?? [];
  const exportBadge = errors.length > 0
    ? '<span class="badge badge-error badge-status">Export error</span>'
    : warnings.length > 0
      ? '<span class="badge badge-warn badge-status">Export warning</span>'
      : '<span class="badge badge-subtle badge-status">Export OK</span>';
  const badges = [
    schemaVersion != null ? `<span class="badge badge-subtle">Schema v${escapeHtml(schemaVersion)}</span>` : "",
    exportBadge,
    state.report?.forced ? `<span class="badge badge-warn">Forced export</span>` : "",
  ].filter(Boolean);
  els.titleBadges.innerHTML = badges.join("");
}

function populateFilters() {
  const library = state.library;
  if (!library) {
    return;
  }

  const seriesOptions = ["all", ...SERIES_FILTERS.map((item) => item.value)];
  const batches = ["all", ...(library.filters?.batchIds ?? [])];
  const sheets = ["all", ...(library.filters?.sheetNames ?? [])];
  const sampleIds = new Set((library.samples ?? []).map((sample) => sample.id));
  const assetGroups = ["all", ...((state.report?.assetStats?.sampleKeys ?? []).filter((value) => sampleIds.has(value)))];

  els.seriesFilter.innerHTML = seriesOptions
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All series" : value)}</option>`)
    .join("");
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

function renderGlassCardGrid(entries, cardClass, emptyMessage) {
  if (!entries.length) {
    return `<div class="muted">${escapeHtml(emptyMessage)}</div>`;
  }
  return `
    <div class="glass-grid ${escapeHtml(cardClass)}">
      ${entries
        .map(
          ([label, value]) => `
            <div class="glass-card">
              <div class="glass-label">${escapeHtml(label)}</div>
              <div class="glass-value">${escapeHtml(value)}</div>
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

function basename(value) {
  const text = String(value ?? "");
  const parts = text.split(/[\\/]/);
  return parts[parts.length - 1] ?? text;
}

function stripExtension(value) {
  return String(value ?? "").replace(/\.[^.]+$/, "");
}

function shortenText(value, maxLength) {
  const text = String(value ?? "").trim();
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function chartFullLabel(chart) {
  return basename(chart.source_file ?? chart.title ?? chart.display_name ?? chart.asset_key ?? "chart");
}

function chartTitle(chart) {
  const source = stripExtension(chart.source_file ?? chart.title ?? chart.display_name ?? chart.asset_key ?? "chart")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return shortenText(source || "Chart", 34);
}

function chartSizeLabel(chart) {
  return formatBytes(chart.size_bytes ?? 0);
}

async function copyTextToClipboard(text) {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (error) {
      // Fall through to legacy copy below.
    }
  }

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();
  textarea.setSelectionRange(0, textarea.value.length);
  let copied = false;
  try {
    copied = document.execCommand("copy");
  } catch (error) {
    copied = false;
  }
  document.body.removeChild(textarea);
  return copied;
}

function flashCopiedFeedback(button, copied) {
  if (!button) {
    return;
  }
  const original = button.dataset.originalLabel ?? button.textContent;
  button.dataset.originalLabel = original;
  button.textContent = copied ? "Copied" : "Copy failed";
  window.clearTimeout(button._copyFeedbackTimer);
  button._copyFeedbackTimer = window.setTimeout(() => {
    button.textContent = button.dataset.originalLabel ?? original;
  }, copied ? 1200 : 1600);
}

function renderMetadata(sample) {
  const ordered = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata
    : Object.entries(sample.metadata ?? {}).map(([key, value]) => ({ key, value }));
  const numericEntries = Object.entries(sample.numericDisplay ?? {}).filter(([, value]) => !isEmptyMetadataValue(value));
  const additionalMetadata = ordered.filter(
    (item) => !isDuplicateMetadataKey(item.key) && !isEmptyMetadataValue(item.value),
  );
  return `
    <div class="detail-section">
      <div class="section-title">Overview</div>
      ${renderFactList([
        ["Updated", formatUtcTimestamp(sample.updatedAt)],
        ["Batch", sample.batchId ?? ""],
        ["Substrate", sample.substrateDisplay || sample.substrateRaw || ""],
      ])}
    </div>
    <div class="detail-section">
      <div class="section-title">Numeric tags</div>
      ${renderGlassCardGrid(numericEntries, "glass-grid-metrics", "None")}
    </div>
    ${additionalMetadata.length
      ? `
        <div class="detail-section">
          <div class="section-title">Additional metadata</div>
          ${renderGlassCardGrid(
            additionalMetadata.map((item) => [item.key, item.value ?? ""]),
            "glass-grid-metadata",
            "None",
          )}
        </div>
      `
      : ""}
  `;
}

function selectedSample() {
  const sample = (state.library?.samples ?? []).find((item) => item.id === state.selectedKey);
  return sample ?? null;
}

function renderChartCard(chart) {
  const fullLabel = chartFullLabel(chart);
  const shortTitle = chartTitle(chart);
  const sizeLabel = chartSizeLabel(chart);
  return `
    <article class="chart-card" title="${escapeHtml(fullLabel)}">
      <div class="chart-card-thumb">
        <img loading="lazy" src="${escapeHtml(chart.url)}" alt="${escapeHtml(fullLabel)}" />
      </div>
      <div class="chart-card-body">
        <div class="chart-card-title">${escapeHtml(shortTitle)}</div>
        <div class="chart-card-meta">
          <span class="chart-card-size">${escapeHtml(sizeLabel)}</span>
          <span class="chart-card-file" title="${escapeHtml(fullLabel)}">${escapeHtml(shortenText(fullLabel, 46))}</span>
        </div>
        <div class="chart-card-actions">
          <button type="button" class="action-button" data-action="copy-chart-link" data-chart-url="${escapeHtml(chart.url)}">
            Copy link
          </button>
          <a class="action-link" href="${escapeHtml(chart.url)}" target="_blank" rel="noopener noreferrer">
            Open in new tab
          </a>
        </div>
      </div>
    </article>
  `;
}

function renderChartsPanel() {
  const sample = selectedSample();
  if (!sample) {
    els.chartsHint.textContent = "Select a sample row";
    els.chartsBody.innerHTML = `<div class="muted">No sample selected.</div>`;
    return;
  }

  const charts = sampleCharts(sample.id);
  els.chartsHint.textContent = sample.displayName;

  if (charts.length === 0) {
    els.chartsBody.innerHTML = `<div class="muted">No chart images were exported for this sample.</div>`;
    return;
  }

  els.chartsBody.innerHTML = `
    <div class="chart-gallery" aria-label="chart gallery">
      ${charts.map((chart) => renderChartCard(chart)).join("")}
    </div>
  `;
}

function renderDetail() {
  const sample = selectedSample();
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
  `;
}

function renderReport() {
  const report = state.report ?? {};
  const warnings = report.warnings ?? [];
  const errors = report.errors ?? [];
  const hasIssues = warnings.length > 0 || errors.length > 0;
  const panel = els.reportBody.closest(".report-panel");
  if (panel) {
    panel.hidden = !hasIssues;
  }
  if (!hasIssues) {
    els.reportStatus.textContent = "";
    els.reportBody.innerHTML = "";
    return;
  }
  const thresholds = report.thresholds ?? {};
  const assets = report.assetStats?.assets ?? [];
  const sampleKeys = Array.from(new Set(assets.map((asset) => asset.sample_key).filter(Boolean)));

  els.reportBody.innerHTML = `
    <details class="report-details">
      <summary>Report details</summary>
      <div class="report-details-body">
        ${renderKeyValueGrid([["Exported at", report.exportedAt ?? ""]])}
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
              warnings
                .map(
                  (warning) => `
                    <div class="warning">
                      <div><strong>${escapeHtml(warning.code)}</strong></div>
                      <div class="muted">${escapeHtml(warning.message)}</div>
                    </div>
                  `,
                )
                .join("")
            }
          </div>
        </div>
        <div class="detail-section">
          <div class="section-title">Errors</div>
          <div class="error-list">
            ${
              errors
                .map(
                  (error) => `
                    <div class="error">
                      <div><strong>${escapeHtml(error.code)}</strong></div>
                      <div class="muted">${escapeHtml(error.message)}</div>
                    </div>
                  `,
                )
                .join("")
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
  renderChartsPanel();
  renderReport();
  els.status.textContent = `${filteredSamples().length} samples visible`;
}

function selectSample(sampleKey) {
  state.selectedKey = sampleKey;
  renderTable();
  renderDetail();
  renderChartsPanel();
}

function attachEvents() {
  els.chartsBody.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-action]");
    if (!button) {
      return;
    }
    if (button.dataset.action === "copy-chart-link") {
      const copied = await copyTextToClipboard(button.dataset.chartUrl ?? "");
      flashCopiedFeedback(button, copied);
    }
  });

  els.search.addEventListener("input", (event) => {
    state.filters.search = event.target.value;
    renderTable();
    els.status.textContent = `${filteredSamples().length} samples visible`;
  });
  els.seriesFilter.addEventListener("change", (event) => {
    state.filters.series = event.target.value;
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
  els.seriesFilter = byId("series-filter");
  els.batchFilter = byId("batch-filter");
  els.sheetFilter = byId("sheet-filter");
  els.assetFilter = byId("asset-filter");
  els.chartOnly = byId("chart-only");
  els.tableCount = byId("table-count");
  els.sampleTable = byId("sample-table");
  els.detailHint = byId("detail-hint");
  els.detailBody = byId("detail-body");
  els.chartsHint = byId("charts-hint");
  els.chartsBody = byId("charts-body");
  els.titleBadges = byId("title-badges");
  els.reportStatus = byId("report-status");
  els.reportBody = byId("report-body");
  const reportPanel = els.reportBody.closest(".report-panel");
  if (reportPanel) {
    reportPanel.hidden = true;
  }

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
