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
};

const WORKSPACE_SPLIT_STORAGE_KEY = "spinlab.web-library.split-ratio";
const WORKSPACE_MIN_SAMPLES_WIDTH = 420;
const WORKSPACE_MIN_DETAIL_WIDTH = 360;
const WORKSPACE_SPLITTER_WIDTH = 12;
const WORKSPACE_STACK_BREAKPOINT = 900;
const WORKSPACE_DEFAULT_RATIO = 0.58;
const WORKSPACE_MIN_RATIO = 0.3;
const WORKSPACE_MAX_RATIO = 0.7;
const TABLE_COLUMN_DEFS = [
  { key: "sample", label: "Sample" },
  { key: "substrate", label: "Substrate" },
  { key: "updated", label: "Updated" },
  { key: "charts", label: "Charts" },
];

const layoutState = {
  splitRatio: WORKSPACE_DEFAULT_RATIO,
  resizeObserver: null,
  detailHeightObserver: null,
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

const NATURAL_COLLATOR = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: "base",
});

const SEARCH_TOKEN_RE = /[\p{L}\p{N}]+/gu;
const SEARCH_COMPACT_RE = /[^\p{L}\p{N}]+/gu;
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

function setupSampleTableStructure() {
  if (!els.sampleTableTable) {
    return;
  }

  els.sampleTableTable.classList.add("sample-table");

  const thead = els.sampleTableTable.querySelector("thead");
  const headerRow = thead?.querySelector("tr");
  if (!thead || !headerRow) {
    return;
  }

  els.sampleTableColgroup = document.createElement("colgroup");
  els.sampleTableColgroup.innerHTML = TABLE_COLUMN_DEFS
    .map((definition) => `<col data-column="${escapeHtml(definition.key)}" />`)
    .join("");
  els.sampleTableTable.insertBefore(els.sampleTableColgroup, thead);

  headerRow.innerHTML = TABLE_COLUMN_DEFS
    .map(
      (definition) => `
        <th class="sample-th sample-th-${escapeHtml(definition.key)}" data-column="${escapeHtml(definition.key)}">
          <span class="sample-th-label">${escapeHtml(definition.label)}</span>
        </th>
      `,
    )
    .join("");
}

function readStoredSplitRatio() {
  try {
    const value = window.localStorage.getItem(WORKSPACE_SPLIT_STORAGE_KEY);
    if (value == null) {
      return WORKSPACE_DEFAULT_RATIO;
    }
    const parsed = Number.parseFloat(value);
    if (!Number.isFinite(parsed)) {
      return WORKSPACE_DEFAULT_RATIO;
    }
    return Math.min(WORKSPACE_MAX_RATIO, Math.max(WORKSPACE_MIN_RATIO, parsed));
  } catch (error) {
    return WORKSPACE_DEFAULT_RATIO;
  }
}

function storeSplitRatio(value) {
  try {
    window.localStorage.setItem(WORKSPACE_SPLIT_STORAGE_KEY, String(value));
  } catch (error) {
    // Ignore storage failures and keep the current layout in memory.
  }
}

function workspaceSplitterWidth() {
  return WORKSPACE_SPLITTER_WIDTH;
}

function workspaceIsStacked() {
  const workspace = els.workspace;
  return !workspace || workspace.classList.contains("is-stacked");
}

function syncTablePanelHeight() {
  if (!els.tablePanel || !els.detailPanel) {
    return;
  }
  if (workspaceIsStacked()) {
    els.tablePanel.style.removeProperty("height");
    return;
  }
  const h = els.detailPanel.getBoundingClientRect().height;
  if (h > 0) {
    els.tablePanel.style.height = `${h}px`;
  }
}

function syncWorkspaceLayout() {
  const workspace = els.workspace;
  if (!workspace) {
    return;
  }

  const width = workspace.clientWidth;
  const minRequiredWidth = WORKSPACE_MIN_SAMPLES_WIDTH + WORKSPACE_MIN_DETAIL_WIDTH + workspaceSplitterWidth();
  if (width < Math.max(WORKSPACE_STACK_BREAKPOINT, minRequiredWidth)) {
    workspace.classList.add("is-stacked");
    workspace.classList.remove("is-split");
    workspace.style.removeProperty("grid-template-columns");
    workspace.style.removeProperty("grid-template-rows");
    if (els.workspaceSplitter) {
      els.workspaceSplitter.hidden = true;
    }
    syncTablePanelHeight();
    return;
  }

  workspace.classList.remove("is-stacked");
  workspace.classList.add("is-split");
  workspace.style.gridTemplateRows = "auto auto";

  const available = Math.max(0, width - workspaceSplitterWidth());
  let leftWidth = Math.round(available * layoutState.splitRatio);
  const maxLeftWidth = Math.max(WORKSPACE_MIN_SAMPLES_WIDTH, available - WORKSPACE_MIN_DETAIL_WIDTH);
  leftWidth = Math.min(maxLeftWidth, Math.max(WORKSPACE_MIN_SAMPLES_WIDTH, leftWidth));
  const rightWidth = Math.max(WORKSPACE_MIN_DETAIL_WIDTH, available - leftWidth);
  leftWidth = Math.max(WORKSPACE_MIN_SAMPLES_WIDTH, available - rightWidth);
  layoutState.splitRatio = available > 0 ? leftWidth / available : WORKSPACE_DEFAULT_RATIO;
  workspace.style.gridTemplateColumns = `${leftWidth}px ${workspaceSplitterWidth()}px ${rightWidth}px`;

  if (els.workspaceSplitter) {
    els.workspaceSplitter.hidden = false;
    els.workspaceSplitter.setAttribute("aria-valuenow", String(Math.round(layoutState.splitRatio * 100)));
    els.workspaceSplitter.setAttribute("aria-valuetext", `${Math.round(layoutState.splitRatio * 100)}% Samples width`);
  }
  syncTablePanelHeight();
}

function setWorkspaceSplitRatio(ratio, persist = true) {
  const normalized = Math.min(WORKSPACE_MAX_RATIO, Math.max(WORKSPACE_MIN_RATIO, ratio));
  layoutState.splitRatio = normalized;
  if (persist) {
    storeSplitRatio(normalized);
  }
  syncWorkspaceLayout();
}

function updateWorkspaceSplitFromPointer(clientX, persist = true) {
  const workspace = els.workspace;
  if (!workspace || workspaceIsStacked()) {
    return;
  }
  const rect = workspace.getBoundingClientRect();
  const available = Math.max(0, rect.width - workspaceSplitterWidth());
  if (available <= 0) {
    return;
  }

  const leftWidth = Math.min(
    available - WORKSPACE_MIN_DETAIL_WIDTH,
    Math.max(WORKSPACE_MIN_SAMPLES_WIDTH, clientX - rect.left),
  );
  const normalized = leftWidth / available;
  setWorkspaceSplitRatio(normalized, persist);
}

function beginWorkspaceSplitDrag(event) {
  if (event.button !== 0 || workspaceIsStacked()) {
    return;
  }
  event.preventDefault();
  const handle = event.currentTarget;
  handle.setPointerCapture(event.pointerId);
  document.body.classList.add("is-resizing-workspace");
  updateWorkspaceSplitFromPointer(event.clientX, false);

  const onPointerMove = (moveEvent) => {
    updateWorkspaceSplitFromPointer(moveEvent.clientX, false);
  };
  const onPointerUp = () => {
    document.body.classList.remove("is-resizing-workspace");
    window.removeEventListener("pointermove", onPointerMove);
    window.removeEventListener("pointerup", onPointerUp);
    window.removeEventListener("pointercancel", onPointerUp);
    storeSplitRatio(layoutState.splitRatio);
  };

  window.addEventListener("pointermove", onPointerMove);
  window.addEventListener("pointerup", onPointerUp, { once: true });
  window.addEventListener("pointercancel", onPointerUp, { once: true });
}

function handleWorkspaceSplitterKeydown(event) {
  if (workspaceIsStacked()) {
    return;
  }
  const step = event.shiftKey ? 0.05 : 0.02;
  if (event.key === "ArrowLeft") {
    event.preventDefault();
    setWorkspaceSplitRatio(layoutState.splitRatio - step);
  } else if (event.key === "ArrowRight") {
    event.preventDefault();
    setWorkspaceSplitRatio(layoutState.splitRatio + step);
  } else if (event.key === "Home") {
    event.preventDefault();
    setWorkspaceSplitRatio(WORKSPACE_MIN_RATIO);
  } else if (event.key === "End") {
    event.preventDefault();
    setWorkspaceSplitRatio(WORKSPACE_MAX_RATIO);
  }
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
  const queryTokens = query.match(SEARCH_TOKEN_RE) ?? [];
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

function renderTable() {
  const samples = filteredSamples();
  els.tableCount.textContent = `${samples.length} of ${state.library?.samples?.length ?? 0}`;
  els.sampleTable.innerHTML = samples
    .map((sample) => {
      const chartCount = sampleCharts(sample.id).length;
      const selected = sample.id === state.selectedKey ? "selected" : "";
      return `
        <tr class="${selected}" data-sample-key="${escapeHtml(sample.id)}">
          <td class="sample-cell sample-cell-sample">
            <div>${escapeHtml(sample.displayName)}</div>
          </td>
          <td class="sample-cell sample-cell-substrate">${escapeHtml(sample.substrateDisplay || sample.substrateRaw || "")}</td>
          <td class="sample-cell sample-cell-updated">${escapeHtml(formatReadableTimestamp(sample.updatedAt))}</td>
          <td class="sample-cell sample-cell-charts num">${escapeHtml(chartCount)}</td>
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
    ${renderNoteSection(sample)}
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
  const sampleKeys = naturalSort(Array.from(new Set(assets.map((asset) => asset.sample_key).filter(Boolean))));

  els.reportBody.innerHTML = `
    <details class="report-details">
      <summary>Report details</summary>
      <div class="report-details-body">
        ${renderKeyValueGrid([["Exported at", report.exportedAt ?? ""]])}
        <div class="detail-section">
          <div class="section-title">Chart groups</div>
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
  void loadSelectedSampleNote();
}

async function loadSelectedSampleNote() {
  const sample = selectedSample();
  if (!sample) {
    resetNoteState(null, "idle");
    renderDetail();
    return;
  }

  const token = resetNoteState(sample.id, "loading");
  renderDetail();

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

  renderDetail();
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
  renderDetail();
}

function cancelNoteEditMode() {
  state.note.editing = false;
  state.note.error = "";
  state.note.draft = state.note.text;
  state.note.status = "ready";
  renderDetail();
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
  renderDetail();

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
    renderDetail();
    state.note.savedTimer = window.setTimeout(() => {
      if (state.selectedKey === sample.id && state.note.sampleId === sample.id && state.note.status === "saved") {
        state.note.status = "ready";
        renderDetail();
      }
    }, 1200);
  } catch (error) {
    if (token !== state.note.requestToken || state.selectedKey !== sample.id) {
      return;
    }
    state.note.status = "error";
    state.note.error = error instanceof Error ? error.message : "Unable to save note.";
    state.note.editing = true;
    renderDetail();
  }
}

function attachEvents() {
  els.workspaceSplitter.addEventListener("pointerdown", beginWorkspaceSplitDrag);
  els.workspaceSplitter.addEventListener("keydown", handleWorkspaceSplitterKeydown);

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

  els.detailBody.addEventListener("click", (event) => {
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

  els.detailBody.addEventListener("input", (event) => {
    const editor = event.target.closest("[data-note-editor]");
    if (!editor) {
      return;
    }
    state.note.draft = editor.value;
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
  els.assetFilter = byId("asset-filter");
  els.chartOnly = byId("chart-only");
  els.tableCount = byId("table-count");
  els.sampleTable = byId("sample-table");
  els.sampleTableTable = els.sampleTable.closest("table");
  els.detailHint = byId("detail-hint");
  els.detailBody = byId("detail-body");
  els.chartsHint = byId("charts-hint");
  els.chartsBody = byId("charts-body");
  els.titleBadges = byId("title-badges");
  els.reportStatus = byId("report-status");
  els.reportBody = byId("report-body");
  els.workspace = document.querySelector(".workspace");
  els.tablePanel = document.querySelector(".table-panel");
  els.detailPanel = document.querySelector(".detail-panel");
  els.chartsPanel = document.querySelector(".charts-panel");
  els.workspaceSplitter = document.createElement("div");
  els.workspaceSplitter.id = "workspace-splitter";
  els.workspaceSplitter.className = "workspace-splitter";
  els.workspaceSplitter.setAttribute("role", "separator");
  els.workspaceSplitter.setAttribute("aria-orientation", "vertical");
  els.workspaceSplitter.setAttribute("tabindex", "0");
  els.workspaceSplitter.setAttribute("aria-label", "Resize Samples and Detail panels");
  els.workspaceSplitter.setAttribute("aria-valuemin", String(Math.round(WORKSPACE_MIN_RATIO * 100)));
  els.workspaceSplitter.setAttribute("aria-valuemax", String(Math.round(WORKSPACE_MAX_RATIO * 100)));
  if (els.workspace && els.detailPanel) {
    els.workspace.insertBefore(els.workspaceSplitter, els.detailPanel);
  }
  layoutState.splitRatio = readStoredSplitRatio();
  setupSampleTableStructure();
  syncWorkspaceLayout();

  window.addEventListener("resize", syncWorkspaceLayout);
  if (window.ResizeObserver) {
    layoutState.resizeObserver = new ResizeObserver(() => {
      syncWorkspaceLayout();
    });
    if (els.workspace) {
      layoutState.resizeObserver.observe(els.workspace);
    }
    layoutState.detailHeightObserver = new ResizeObserver(syncTablePanelHeight);
    if (els.detailPanel) {
      layoutState.detailHeightObserver.observe(els.detailPanel);
    }
  }

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
    syncWorkspaceLayout();
    void loadSelectedSampleNote();
  } catch (error) {
    els.status.textContent = "Load failed";
    els.detailBody.innerHTML = `<div class="error"><strong>Unable to load export data.</strong><div class="muted">${escapeHtml(error.message)}</div></div>`;
  }
}

main();
