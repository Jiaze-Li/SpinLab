const state = {
  library: null,
  report: null,
  selectedKey: null,
  note: {
    sampleId: null,
    status: "idle",
    error: "",
    text: "",
    draft: "",
    editing: false,
    requestToken: 0,
    savedTimer: null,
  },
  filters: {
    search: "",
    series: "all",
    batch: "all",
    assetGroup: "all",
    chartsOnly: false,
  },
  lightbox: {
    open: false,
    charts: [],
    index: 0,
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

function formatReadableTimestamp(value) {
  if (!value) {
    return "";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

const THRESHOLD_LABELS = {
  chartBytesWarn: "Chart size warning",
  chartBytesFail: "Chart size failure",
  imageBytesWarn: "Image size warning",
  imageBytesFail: "Image size failure",
  imageCountWarn: "Image count warning",
  imageCountFail: "Image count failure",
};

const THRESHOLD_BYTE_KEYS = new Set(["chartBytesWarn", "chartBytesFail", "imageBytesWarn", "imageBytesFail"]);
const THRESHOLD_COUNT_KEYS = new Set(["imageCountWarn", "imageCountFail"]);

function formatThresholdBytes(bytes) {
  if (!Number.isFinite(bytes)) {
    return String(bytes);
  }
  const units = [
    ["GB", 1024 ** 3],
    ["MB", 1024 ** 2],
    ["KB", 1024],
  ];
  for (const [unit, size] of units) {
    if (bytes >= size) {
      const value = bytes / size;
      const rounded = Number.isInteger(value) ? value : Math.round(value * 10) / 10;
      return `${rounded} ${unit}`;
    }
  }
  return `${bytes} B`;
}

function formatThresholdValue(key, value) {
  if (typeof value !== "number") {
    return String(value ?? "");
  }
  if (THRESHOLD_BYTE_KEYS.has(key)) {
    return formatThresholdBytes(value);
  }
  if (THRESHOLD_COUNT_KEYS.has(key)) {
    return value.toLocaleString();
  }
  return value.toLocaleString();
}

const NATURAL_COLLATOR = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: "base",
});

const SEARCH_TOKEN_RE = /[\p{L}\p{N}]+/gu;
const SEARCH_COMPACT_RE = /[^\p{L}\p{N}]+/gu;
const SEARCH_QUERY_TOKEN_RE = /-?\d+(?:\.\d+)?(?:[°µμ]?[a-z]+)?|[\p{L}\p{N}]+/gu;
const NUMERIC_QUERY_RE = /^(-?\d+(?:\.\d+)?)([a-z°µμ]+)$/i;
const NUMERIC_VALUE_RE = /^(-?\d+(?:\.\d+)?)\s*(?:([°µμ]))?\s*([\p{L}]+)$/u;
const MODIFIER_QUERY_TOKENS = new Set(["o", "b", "hf"]);

function sampleCharts(sampleKey) {
  return (state.report?.assetStats?.assets ?? []).filter((asset) => asset.sample_key === sampleKey);
}

function naturalCompare(left, right) {
  return NATURAL_COLLATOR.compare(String(left ?? ""), String(right ?? ""));
}

function naturalSort(values) {
  return [...values].sort(naturalCompare);
}

function inferSeriesToken(value) {
  const text = String(value ?? "").normalize("NFKC").trim();
  if (!text) {
    return "";
  }
  const token = text.match(/^[\p{L}\p{N}]+/u)?.[0] ?? "";
  if (!token) {
    return "";
  }
  const prefix = token.match(/^[\p{L}]+/u)?.[0] ?? "";
  if (prefix.length < 2 || (prefix.length > 4 && !/\d/.test(token))) {
    return "";
  }
  return prefix.toUpperCase();
}

function sampleSeriesValues(sample) {
  return naturalSort(
    Array.from(
      new Set([
        inferSeriesToken(sample.id),
        inferSeriesToken(sample.batchId),
        inferSeriesToken(sample.displayName),
      ].filter(Boolean)),
    ),
  );
}

function librarySeriesValues(samples) {
  const values = new Set();
  for (const sample of samples) {
    for (const series of sampleSeriesValues(sample)) {
      values.add(series);
    }
  }
  return naturalSort(Array.from(values));
}

function normalizeSearchText(value) {
  return String(value ?? "").normalize("NFKC").toLowerCase();
}

function tokenizeSearchText(value) {
  return normalizeSearchText(value).match(SEARCH_TOKEN_RE) ?? [];
}

function compactSearchToken(value) {
  return normalizeSearchText(value).replace(SEARCH_COMPACT_RE, "");
}

function addSearchText(index, value) {
  if (value == null) {
    return;
  }
  const text = String(value);
  if (!text) {
    return;
  }
  for (const token of tokenizeSearchText(text)) {
    index.tokens.add(token);
  }
  const compact = compactSearchToken(text);
  if (compact) {
    index.tokens.add(compact);
  }
}

function addStructuredIdentifierTokens(index, value) {
  const text = String(value ?? "").normalize("NFKC").trim();
  if (!text) {
    return;
  }

  const segments = text
    .split(/[|/]+/)
    .map((segment) => segment.trim())
    .filter(Boolean);
  if (segments.length === 0) {
    return;
  }

  for (const segment of segments) {
    addSearchText(index, segment);
    index.modifierTokens.add(tokenizeSearchText(segment)[0] ?? compactSearchToken(segment));
  }

  const tail = segments.slice(-2);
  if (tail.length === 2) {
    const material = tail[0].replace(/[^A-Za-z]+/g, "").toLowerCase();
    const orientation = tail[1].replace(/[^A-Za-z0-9]+/g, "").toLowerCase();
    if (material && orientation) {
      index.tokens.add(`${material}${orientation}`);
    }
  }

  const compact = compactSearchToken(text);
  if (compact) {
    index.tokens.add(compact);
  }
}

function normalizeNumericUnit(unit) {
  const compact = normalizeSearchText(unit).replace(/[^a-z0-9°]+/g, "").replace(/^°/, "");
  if (compact === "ps" || compact === "p") {
    return "p";
  }
  if (compact === "c" || compact === "°c") {
    return "c";
  }
  if (compact === "mt") {
    return "mt";
  }
  if (compact === "mj") {
    return "mj";
  }
  return compact;
}

function parseNumericValue(value) {
  const text = normalizeSearchText(value).trim();
  if (!text) {
    return null;
  }
  const match = text.match(NUMERIC_VALUE_RE);
  if (!match) {
    return null;
  }
  const amount = Number.parseFloat(match[1]);
  if (!Number.isFinite(amount)) {
    return null;
  }
  const unit = normalizeNumericUnit(`${match[2] ?? ""}${match[3] ?? ""}`);
  if (!unit) {
    return null;
  }
  return { amount, unit };
}

function parseSearchToken(token) {
  const normalized = normalizeSearchText(token);
  const match = normalized.match(NUMERIC_QUERY_RE);
  if (!match) {
    return { kind: "text", token: normalized };
  }
  const amount = Number.parseFloat(match[1]);
  if (!Number.isFinite(amount)) {
    return { kind: "text", token: normalized };
  }
  return {
    kind: "numeric",
    amount,
    unit: normalizeNumericUnit(match[2]),
    token: normalized,
  };
}

function sampleSearchIndex(sample) {
  const index = {
    tokens: new Set(),
    modifierTokens: new Set(),
    numericValues: [],
  };
  const textValues = [
    sample.displayName,
    sample.id,
    sample.batchId,
    sample.substrateRaw,
    sample.substrateDisplay,
    ...(sample.substrateTokens ?? []),
    ...(sample.substrateTags ?? []),
  ];

  addStructuredIdentifierTokens(index, sample.id);
  addStructuredIdentifierTokens(index, sample.batchId);
  addStructuredIdentifierTokens(index, sample.displayName);

  const metadataEntries = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata.map((item) => [item.key, item.value])
    : Object.entries(sample.metadata ?? {});

  for (const [key, value] of metadataEntries) {
    textValues.push(key, value);
  }
  for (const [key, value] of Object.entries(sample.metadata ?? {})) {
    textValues.push(key, value);
  }
  for (const [key, value] of Object.entries(sample.numericDisplay ?? {})) {
    textValues.push(key, value);
  }
  for (const [key, value] of Object.entries(sample.numericTags ?? {})) {
    textValues.push(key, value);
  }

  for (const value of textValues) {
    addSearchText(index, value);
    const parsed = parseNumericValue(value);
    if (parsed) {
      index.numericValues.push(parsed);
    }
  }

  return index;
}

function sampleSearchQueryMatches(sample, search) {
  const query = search.trim();
  if (!query) {
    return true;
  }

  const { numericValues, modifierTokens, tokens } = sampleSearchIndex(sample);
  const queryTokens = query.match(SEARCH_QUERY_TOKEN_RE) ?? [];
  if (queryTokens.length === 0) {
    return true;
  }

  for (const rawToken of queryTokens) {
    const token = parseSearchToken(rawToken);
    if (token.kind === "numeric") {
      const isFuzzyUnit = token.unit === "mt" || token.unit === "mj";
      const numericMatch = numericValues.some((candidate) => {
        if (candidate.unit !== token.unit) {
          return false;
        }
        return isFuzzyUnit
          ? Math.abs(candidate.amount - token.amount) <= 8
          : candidate.amount === token.amount;
      });
      if (numericMatch) {
        continue;
      }
    }

    if (MODIFIER_QUERY_TOKENS.has(token.token)) {
      if (!modifierTokens.has(token.token)) {
        return false;
      }
      continue;
    }

    if (!tokens.has(token.token)) {
      return false;
    }
  }

  return true;
}

function compareSamples(left, right) {
  const idCompare = naturalCompare(left.id, right.id);
  if (idCompare !== 0) {
    return idCompare;
  }
  const batchCompare = naturalCompare(left.batchId, right.batchId);
  if (batchCompare !== 0) {
    return batchCompare;
  }
  return naturalCompare(left.displayName, right.displayName);
}

function sampleMatchesSeries(sample, series) {
  if (series === "all") {
    return true;
  }
  return sampleSeriesValues(sample).includes(series);
}

function sampleMatches(sample) {
  const search = state.filters.search.trim();
  const charts = sampleCharts(sample.id);
  if (!sampleMatchesSeries(sample, state.filters.series)) {
    return false;
  }
  if (state.filters.batch !== "all" && sample.batchId !== state.filters.batch) {
    return false;
  }
  if (state.filters.assetGroup !== "all" && !charts.some((asset) => asset.sample_key === state.filters.assetGroup)) {
    return false;
  }
  if (state.filters.chartsOnly && charts.length === 0) {
    return false;
  }
  if (!search) {
    return true;
  }
  return sampleSearchQueryMatches(sample, search);
}

function filteredSamples() {
  return (state.library?.samples ?? []).filter(sampleMatches).sort(compareSamples);
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

function renderGlobalCounts() {
  const summary = state.library?.sourceSummary ?? {};
  const report = state.report ?? {};
  const assetStats = report.assetStats ?? {};
  const sampleCount = summary.sampleCount ?? state.library?.samples?.length ?? 0;
  const chartCount = assetStats.chartCount ?? 0;
  els.globalCounts.textContent = `${sampleCount} samples · ${chartCount} charts`;
}

function populateFilters() {
  const library = state.library;
  if (!library) {
    return;
  }

  const seriesOptions = ["all", ...librarySeriesValues(library.samples ?? [])];
  const batches = ["all", ...naturalSort(library.filters?.batchIds ?? [])];
  const sampleIds = new Set((library.samples ?? []).map((sample) => sample.id));
  const assetGroups = ["all", ...naturalSort((state.report?.assetStats?.sampleKeys ?? []).filter((value) => sampleIds.has(value)))];

  els.seriesFilter.innerHTML = seriesOptions
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All series" : value)}</option>`)
    .join("");
  els.batchFilter.innerHTML = batches
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All batches" : value)}</option>`)
    .join("");
  els.assetFilter.innerHTML = assetGroups
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value === "all" ? "All chart groups" : assetGroupLabel(value))}</option>`)
    .join("");
}

function renderSampleList() {
  const samples = filteredSamples();
  els.tableCount.textContent = `${samples.length} of ${state.library?.samples?.length ?? 0}`;
  els.sampleList.innerHTML = samples
    .map((sample) => {
      const chartCount = sampleCharts(sample.id).length;
      const selected = sample.id === state.selectedKey;
      return `
        <div class="sample-row${selected ? " selected" : ""}" data-sample-key="${escapeHtml(sample.id)}" role="option" aria-selected="${selected}">
          <span class="sample-row-name">${escapeHtml(sample.displayName)}</span>
          <span class="sample-row-charts">${escapeHtml(chartCount)}</span>
        </div>
      `;
    })
    .join("");

  Array.from(els.sampleList.querySelectorAll(".sample-row")).forEach((row) => {
    row.addEventListener("click", () => selectSample(row.dataset.sampleKey));
  });
}

function renderFieldList(entries, emptyMessage) {
  if (!entries.length) {
    return emptyMessage ? `<div class="muted">${escapeHtml(emptyMessage)}</div>` : "";
  }
  return `
    <div class="field-list">
      ${entries
        .map(
          ([label, value]) => `
            <div class="field-row">
              <div class="field-label">${escapeHtml(label)}</div>
              <div class="field-value">${escapeHtml(value)}</div>
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

function chartFullLabel(chart) {
  return basename(chart.source_file ?? chart.title ?? chart.display_name ?? chart.asset_key ?? "chart");
}

function noteApiUrl(sampleId) {
  return `./api/note?sample_id=${encodeURIComponent(sampleId)}`;
}

function clearNoteSavedTimer() {
  if (state.note.savedTimer) {
    window.clearTimeout(state.note.savedTimer);
    state.note.savedTimer = null;
  }
}

function resetNoteState(sampleId, status = "loading") {
  clearNoteSavedTimer();
  state.note.sampleId = sampleId;
  state.note.status = status;
  state.note.error = "";
  state.note.text = "";
  state.note.draft = "";
  state.note.editing = false;
  state.note.requestToken += 1;
  return state.note.requestToken;
}

function renderNoteSection(sample) {
  const note = state.note;
  const active = note.sampleId === sample.id;
  if (!active) {
    return `
      <div class="detail-section note-section">
        <div class="detail-section-head">
          <div class="section-title">Note</div>
          <button type="button" class="action-button action-button-secondary" disabled>Edit</button>
        </div>
        <div class="note-card">
          <div class="note-text muted">Loading note...</div>
        </div>
      </div>
    `;
  }
  const statusText =
    note.status === "loading"
      ? "Loading note..."
      : note.status === "saving"
        ? "Saving..."
        : note.status === "saved"
          ? "Saved"
          : note.status === "error"
            ? note.error
            : "";

  if (note.editing && active) {
    return `
      <div class="detail-section note-section">
        <div class="detail-section-head">
          <div class="section-title">Note</div>
          <div class="note-actions">
            <button type="button" class="action-button action-button-secondary" data-note-action="cancel" ${note.status === "saving" ? "disabled" : ""}>Cancel</button>
            <button type="button" class="action-button" data-note-action="save" ${note.status === "saving" ? "disabled" : ""}>Save</button>
          </div>
        </div>
        <textarea class="note-editor" data-note-editor="true" spellcheck="true" aria-label="Sample note" ${note.status === "saving" ? "disabled" : ""}>${escapeHtml(note.draft)}</textarea>
        ${statusText ? `<div class="note-status ${note.status === "error" ? "note-error" : ""}">${escapeHtml(statusText)}</div>` : ""}
      </div>
    `;
  }

  return `
    <div class="detail-section note-section">
      <div class="detail-section-head">
        <div class="section-title">Note</div>
        <button type="button" class="action-button action-button-secondary" data-note-action="edit" ${note.status === "loading" || note.status === "saving" || note.status === "error" ? "disabled" : ""}>Edit</button>
      </div>
      <div class="note-card">
        ${note.status === "loading" && active
          ? `<div class="note-text muted">Loading note...</div>`
          : note.status === "error" && active
            ? `<div class="note-status note-error">${escapeHtml(statusText)}</div>`
            : note.text.length === 0 && active
              ? `<div class="note-text muted">No note yet.</div>`
              : `<div class="note-text">${escapeHtml(note.text)}</div>`}
      </div>
      ${note.status === "saved" && active ? `<div class="note-status note-ok">Saved</div>` : ""}
    </div>
  `;
}

function renderIdentityBlock(sample) {
  return `
    <div class="identity-block">
      <div class="identity-title">${escapeHtml(sample.displayName)}</div>
    </div>
  `;
}

function renderMetadataPanel(sample) {
  const ordered = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata
    : Object.entries(sample.metadata ?? {}).map(([key, value]) => ({ key, value }));
  const numericEntries = Object.entries(sample.numericDisplay ?? {}).filter(([, value]) => !isEmptyMetadataValue(value));
  const additionalMetadata = ordered.filter(
    (item) => !isDuplicateMetadataKey(item.key) && !isEmptyMetadataValue(item.value),
  );
  return `
    ${renderIdentityBlock(sample)}
    <div class="detail-section">
      <div class="section-title">Numeric tags</div>
      ${renderFieldList(numericEntries, "None")}
    </div>
    ${additionalMetadata.length
      ? `
        <div class="detail-section">
          <div class="section-title">Additional metadata</div>
          ${renderFieldList(additionalMetadata.map((item) => [item.key, item.value ?? ""]))}
        </div>
      `
      : ""}
    ${renderNoteSection(sample)}
  `;
}

function selectedSample() {
  const sample = (state.library?.samples ?? []).find((item) => item.id === state.selectedKey);
  return sample ?? null;
}

function renderChartCard(chart, index) {
  const fullLabel = chartFullLabel(chart);
  return `
    <article class="chart-card" title="${escapeHtml(fullLabel)}" data-chart-index="${index}">
      <img loading="lazy" src="${escapeHtml(chart.url)}" alt="${escapeHtml(fullLabel)}" />
    </article>
  `;
}

function renderChartsNav() {
  const samples = filteredSamples();
  const index = samples.findIndex((sample) => sample.id === state.selectedKey);
  const hasSamples = samples.length > 0 && index !== -1;

  els.chartNavPrev.disabled = !hasSamples || index <= 0;
  els.chartNavNext.disabled = !hasSamples || index >= samples.length - 1;
  els.chartNavPosition.textContent = hasSamples ? `${index + 1} of ${samples.length}` : "";
}

function stepSelectedSample(delta) {
  const samples = filteredSamples();
  const index = samples.findIndex((sample) => sample.id === state.selectedKey);
  if (index === -1) {
    return;
  }
  const nextIndex = index + delta;
  if (nextIndex < 0 || nextIndex >= samples.length) {
    return;
  }
  selectSample(samples[nextIndex].id);
}

function renderChartsPanel() {
  const sample = selectedSample();
  renderChartsNav();

  if (!sample) {
    els.chartsSampleName.textContent = "Charts";
    els.chartsBody.innerHTML = `<div class="muted">No sample selected.</div>`;
    return;
  }

  els.chartsSampleName.textContent = sample.displayName;
  const charts = sampleCharts(sample.id);

  if (charts.length === 0) {
    els.chartsBody.innerHTML = `<div class="muted">No chart images were exported for this sample.</div>`;
    return;
  }

  els.chartsBody.innerHTML = `
    <div class="chart-gallery" aria-label="chart gallery">
      ${charts.map((chart, index) => renderChartCard(chart, index)).join("")}
    </div>
  `;
}

function openLightbox(charts, index) {
  if (!charts.length) {
    return;
  }
  state.lightbox = { open: true, charts, index };
  renderLightbox();
}

function closeLightbox() {
  if (!state.lightbox.open) {
    return;
  }
  state.lightbox.open = false;
  renderLightbox();
}

function stepLightbox(delta) {
  if (!state.lightbox.open) {
    return;
  }
  const nextIndex = state.lightbox.index + delta;
  if (nextIndex < 0 || nextIndex >= state.lightbox.charts.length) {
    return;
  }
  state.lightbox.index = nextIndex;
  renderLightbox();
}

function renderLightbox() {
  const { open, charts, index } = state.lightbox;
  els.lightbox.hidden = !open;
  if (!open) {
    els.lightboxImage.src = "";
    els.lightboxImage.alt = "";
    return;
  }
  const chart = charts[index];
  els.lightboxImage.src = chart.url;
  els.lightboxImage.alt = chartFullLabel(chart);
  els.lightboxPrev.disabled = index <= 0;
  els.lightboxNext.disabled = index >= charts.length - 1;
}

function renderMetadata() {
  const sample = selectedSample();
  if (!sample) {
    els.metadataBody.innerHTML = `<div class="muted">Select a sample to see its metadata.</div>`;
    els.metadataUpdated.textContent = "";
    return;
  }
  els.metadataBody.innerHTML = renderMetadataPanel(sample);
  const updated = formatReadableTimestamp(sample.updatedAt);
  els.metadataUpdated.textContent = updated ? `Updated ${updated}` : "";
}

function renderReportIssueList(items, listClass, itemClass) {
  return `
    <div class="${listClass}">
      ${items
        .map(
          (item) => `
            <div class="${itemClass}">
              <div><strong>${escapeHtml(item.code)}</strong></div>
              <div class="muted">${escapeHtml(item.message)}</div>
            </div>
          `,
        )
        .join("")}
    </div>
  `;
}

function renderReportStatus(warnings, errors) {
  if (warnings.length === 0 && errors.length === 0) {
    return `
      <div class="report-status-summary report-status-ok">✓ Export completed successfully</div>
      <div class="muted">No warnings or errors.</div>
    `;
  }

  const counts = [
    warnings.length ? `${warnings.length} warning${warnings.length === 1 ? "" : "s"}` : "",
    errors.length ? `${errors.length} error${errors.length === 1 ? "" : "s"}` : "",
  ].filter(Boolean);

  return `
    <div class="report-status-summary report-status-warn">${escapeHtml(counts.join(", "))}</div>
    ${warnings.length ? renderReportIssueList(warnings, "warning-list", "warning") : ""}
    ${errors.length ? renderReportIssueList(errors, "error-list", "error") : ""}
  `;
}

function renderReport() {
  const report = state.report ?? {};
  const warnings = report.warnings ?? [];
  const errors = report.errors ?? [];
  const hasIssues = warnings.length > 0 || errors.length > 0;
  const thresholds = report.thresholds ?? {};

  els.reportBadge.hidden = !hasIssues;
  els.reportStatus.textContent = report.exportedAt ? `Exported ${formatReadableTimestamp(report.exportedAt)}` : "";

  els.reportBody.innerHTML = `
      <div class="report-details-body">
        <div class="detail-section">
          <div class="section-title">Status</div>
          ${renderReportStatus(warnings, errors)}
        </div>
        <div class="report-divider"></div>
        <div class="detail-section report-thresholds">
          <div class="section-title">Thresholds</div>
          ${renderFieldList(
            Object.entries(thresholds).map(([key, value]) => [
              THRESHOLD_LABELS[key] ?? key,
              formatThresholdValue(key, value),
            ]),
          )}
        </div>
      </div>
  `;
}

function setReportPopoverOpen(open) {
  els.reportPopover.hidden = !open;
  els.reportToggle.setAttribute("aria-expanded", String(open));
}

function toggleReportPopover() {
  setReportPopoverOpen(els.reportPopover.hidden);
}

function reRender() {
  renderGlobalCounts();
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
  renderReport();
  // Header status is cleared on a routine successful load — it only speaks
  // up for "Loading..." and "Load failed" (principle 8: actionable only).
  els.status.textContent = "";
}

function selectSample(sampleKey) {
  state.selectedKey = sampleKey;
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
  void loadSelectedSampleNote();
}

async function loadSelectedSampleNote() {
  const sample = selectedSample();
  if (!sample) {
    resetNoteState(null, "idle");
    renderMetadata();
    return;
  }

  const token = resetNoteState(sample.id, "loading");
  renderMetadata();

  try {
    const response = await fetch(noteApiUrl(sample.id), {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    });
    if (!response.ok) {
      throw new Error(`Failed to load note (${response.status})`);
    }
    const payload = await response.json();
    if (token !== state.note.requestToken || state.selectedKey !== sample.id) {
      return;
    }
    state.note.status = "ready";
    state.note.error = "";
    state.note.text = String(payload.note_text ?? "");
    state.note.draft = state.note.text;
    state.note.editing = false;
  } catch (error) {
    if (token !== state.note.requestToken || state.selectedKey !== sample.id) {
      return;
    }
    state.note.status = "error";
    state.note.error = error instanceof Error ? error.message : "Unable to load note.";
    state.note.editing = false;
  }

  renderMetadata();
}

function enterNoteEditMode() {
  const sample = selectedSample();
  if (!sample || state.note.sampleId !== sample.id || state.note.status === "loading" || state.note.status === "saving") {
    return;
  }
  clearNoteSavedTimer();
  state.note.editing = true;
  state.note.status = "ready";
  state.note.error = "";
  state.note.draft = state.note.text;
  renderMetadata();
}

function cancelNoteEditMode() {
  state.note.editing = false;
  state.note.error = "";
  state.note.draft = state.note.text;
  state.note.status = "ready";
  renderMetadata();
}

async function saveSelectedNote() {
  const sample = selectedSample();
  if (!sample || state.note.sampleId !== sample.id || !state.note.editing || state.note.status === "saving") {
    return;
  }

  const token = ++state.note.requestToken;
  const noteText = state.note.draft ?? "";
  clearNoteSavedTimer();
  state.note.status = "saving";
  state.note.error = "";
  renderMetadata();

  try {
    const response = await fetch("./api/note", {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        sample_id: sample.id,
        note_text: noteText,
      }),
    });
    if (!response.ok) {
      throw new Error(`Failed to save note (${response.status})`);
    }
    const payload = await response.json();
    if (token !== state.note.requestToken || state.selectedKey !== sample.id) {
      return;
    }
    state.note.status = "saved";
    state.note.error = "";
    state.note.text = String(payload.note_text ?? noteText);
    state.note.draft = state.note.text;
    state.note.editing = false;
    renderMetadata();
    state.note.savedTimer = window.setTimeout(() => {
      if (state.selectedKey === sample.id && state.note.sampleId === sample.id && state.note.status === "saved") {
        state.note.status = "ready";
        renderMetadata();
      }
    }, 1200);
  } catch (error) {
    if (token !== state.note.requestToken || state.selectedKey !== sample.id) {
      return;
    }
    state.note.status = "error";
    state.note.error = error instanceof Error ? error.message : "Unable to save note.";
    state.note.editing = true;
    renderMetadata();
  }
}

function attachEvents() {
  els.chartsBody.addEventListener("click", (event) => {
    const card = event.target.closest("[data-chart-index]");
    if (!card) {
      return;
    }
    const sample = selectedSample();
    if (!sample) {
      return;
    }
    const index = Number(card.dataset.chartIndex);
    openLightbox(sampleCharts(sample.id), index);
  });

  els.lightboxClose.addEventListener("click", () => closeLightbox());
  els.lightboxPrev.addEventListener("click", () => stepLightbox(-1));
  els.lightboxNext.addEventListener("click", () => stepLightbox(1));
  els.lightbox.addEventListener("click", (event) => {
    if (event.target === els.lightbox) {
      closeLightbox();
    }
  });

  els.metadataBody.addEventListener("click", (event) => {
    const button = event.target.closest("[data-note-action]");
    if (!button) {
      return;
    }
    const action = button.dataset.noteAction;
    if (action === "edit") {
      enterNoteEditMode();
      return;
    }
    if (action === "cancel") {
      cancelNoteEditMode();
      return;
    }
    if (action === "save") {
      void saveSelectedNote();
    }
  });

  els.metadataBody.addEventListener("input", (event) => {
    const editor = event.target.closest("[data-note-editor]");
    if (!editor) {
      return;
    }
    state.note.draft = editor.value;
  });

  function refilterSampleList() {
    renderSampleList();
    renderChartsNav();
  }

  els.search.addEventListener("input", (event) => {
    state.filters.search = event.target.value;
    refilterSampleList();
  });
  els.seriesFilter.addEventListener("change", (event) => {
    state.filters.series = event.target.value;
    refilterSampleList();
  });
  els.batchFilter.addEventListener("change", (event) => {
    state.filters.batch = event.target.value;
    refilterSampleList();
  });
  els.assetFilter.addEventListener("change", (event) => {
    state.filters.assetGroup = event.target.value;
    refilterSampleList();
  });
  els.chartOnly.addEventListener("change", (event) => {
    state.filters.chartsOnly = event.target.checked;
    refilterSampleList();
  });

  els.chartNavPrev.addEventListener("click", () => stepSelectedSample(-1));
  els.chartNavNext.addEventListener("click", () => stepSelectedSample(1));

  els.reportToggle.addEventListener("click", (event) => {
    event.stopPropagation();
    toggleReportPopover();
  });

  els.reportPopover.addEventListener("click", (event) => {
    event.stopPropagation();
  });

  document.addEventListener("click", (event) => {
    if (!els.reportPopover.hidden && !els.reportToggle.contains(event.target)) {
      setReportPopoverOpen(false);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.lightbox.open) {
      closeLightbox();
      return;
    }
    if (event.key === "Escape" && !els.reportPopover.hidden) {
      setReportPopoverOpen(false);
      return;
    }
    if (event.defaultPrevented || event.altKey || event.metaKey || event.ctrlKey) {
      return;
    }
    if (state.lightbox.open) {
      if (event.key === "ArrowLeft") {
        stepLightbox(-1);
      } else if (event.key === "ArrowRight") {
        stepLightbox(1);
      }
      return;
    }
    const target = event.target;
    const isEditable =
      target instanceof HTMLElement &&
      (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT" || target.isContentEditable);
    if (isEditable) {
      return;
    }
    if (event.key === "ArrowLeft") {
      stepSelectedSample(-1);
    } else if (event.key === "ArrowRight") {
      stepSelectedSample(1);
    }
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
  els.globalCounts = byId("global-counts");
  els.search = byId("search");
  els.seriesFilter = byId("series-filter");
  els.batchFilter = byId("batch-filter");
  els.assetFilter = byId("asset-filter");
  els.chartOnly = byId("chart-only");
  els.tableCount = byId("table-count");
  els.sampleList = byId("sample-list");
  els.metadataBody = byId("metadata-body");
  els.metadataUpdated = byId("metadata-updated");
  els.chartsSampleName = byId("charts-sample-name");
  els.chartNavPrev = byId("chart-nav-prev");
  els.chartNavNext = byId("chart-nav-next");
  els.chartNavPosition = byId("chart-nav-position");
  els.chartsBody = byId("charts-body");
  els.reportToggle = byId("report-toggle");
  els.reportBadge = byId("report-badge");
  els.reportPopover = byId("report-popover");
  els.reportStatus = byId("report-status");
  els.reportBody = byId("report-body");
  els.lightbox = byId("lightbox");
  els.lightboxImage = byId("lightbox-image");
  els.lightboxClose = byId("lightbox-close");
  els.lightboxPrev = byId("lightbox-prev");
  els.lightboxNext = byId("lightbox-next");

  try {
    await loadData();
    state.selectedKey = state.library.samples[0]?.id ?? null;
    populateFilters();
    attachEvents();
    reRender();
    void loadSelectedSampleNote();
  } catch (error) {
    els.status.textContent = "Load failed";
    els.metadataBody.innerHTML = `<div class="error"><strong>Unable to load export data.</strong><div class="muted">${escapeHtml(error.message)}</div></div>`;
  }
}

main();
