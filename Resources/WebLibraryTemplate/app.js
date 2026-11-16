const state = {
  pending: [],
  openGroups: new Set(),
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

// Extension points. A feature (e.g. compare.js) registers an object whose methods wrap the page's own
// functions; each wrapper receives the original function first. Features never reassign page functions.
// Hooks: renderSampleList, renderChartsNav, stepSelectedSample, renderMetadataPanel, renderMetadata,
// attachEvents, reRender.
const features = [];

function registerFeature(feature) {
  features.push(feature);
}

function runFeatureHook(hook, base, args) {
  const feature = features.find((item) => typeof item[hook] === "function");
  return feature ? feature[hook](base, ...args) : base(...args);
}

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
  // MM-DD HH:mm in local time; a date from another year keeps its year (YYYY-MM-DD HH:mm).
  const pad = (n) => String(n).padStart(2, "0");
  const year = date.getFullYear() === new Date().getFullYear() ? "" : `${date.getFullYear()}-`;
  return `${year}${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
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

// Submissions from the phone that SpinLab has not collected yet (read from the cloud inbox).
function pendingSampleName(fields) {
  const one = (material, orientation) => `${fields.batch ?? "?"} - ${material ?? "?"}(${orientation ?? "?"})`;
  const extras = Array.isArray(fields.extraSubstrates) ? fields.extraSubstrates : [];
  const first = one(fields.substrateMaterial, fields.substrateOrientation);
  return extras.length ? `${first} +${extras.length} more` : first;
}

async function refreshPendingSamples() {
  try {
    const response = await fetch("./api/samples", { cache: "no-store" });
    if (!response.ok) return;
    const body = await response.json();
    state.pending = (body.submissions ?? []).filter((item) => item && item.fields);
    renderSampleList();
  } catch {
    // Offline or not signed in: the list simply shows no waiting samples.
  }
}

function renderPendingRows() {
  if (els.search.value.trim()) return "";
  return (state.pending ?? [])
    .map((item) => `
        <div class="sample-row pending" role="option" aria-selected="false">
          <span class="sample-row-name">${escapeHtml(pendingSampleName(item.fields))}</span>
          <span class="sample-row-charts">Awaiting SpinLab</span>
        </div>
      `)
    .join("");
}

// Samples are grouped by batch prefix (PN, PT, LNO …): the letters a batch id starts with.
function batchPrefixOf(sample) {
  const match = /^[A-Za-z]+/.exec(sample.batchId ?? "");
  return match ? match[0].toUpperCase() : "Other";
}

function baseRenderSampleList() {
  const samples = filteredSamples();
  els.tableCount.textContent = `${samples.length} of ${state.library?.samples?.length ?? 0}`;
  const searching = Boolean(els.search.value.trim())
    || [els.seriesFilter, els.batchFilter, els.assetFilter].some((select) => select.value !== "all")
    || els.chartOnly.checked;
  const groups = new Map();
  for (const sample of samples) {
    const prefix = batchPrefixOf(sample);
    if (!groups.has(prefix)) groups.set(prefix, []);
    groups.get(prefix).push(sample);
  }
  const rowHtml = (sample) => {
    const chartCount = sampleCharts(sample.id).length;
    const selected = sample.id === state.selectedKey;
    return `
        <div class="sample-row${selected ? " selected" : ""}" data-sample-key="${escapeHtml(sample.id)}" role="option" aria-selected="${selected}">
          <span class="sample-row-name">${escapeHtml(sample.displayName)}</span>
          <span class="sample-row-charts">${escapeHtml(chartCount)}</span>
        </div>
      `;
  };
  const groupHtml = Array.from(groups, ([prefix, items]) => {
    // A search shows every matching group open; otherwise groups follow the reader's own opening.
    const open = searching || state.openGroups.has(prefix);
    return `
        <div class="sample-group">
          <button type="button" class="sample-group-head" data-group="${escapeHtml(prefix)}" aria-expanded="${open}">
            <span class="sample-group-chevron" aria-hidden="true">${open ? "▾" : "▸"}</span>
            <span class="sample-group-name">${escapeHtml(prefix)}</span>
            <span class="sample-group-count">${items.length}</span>
          </button>
          ${open ? items.map(rowHtml).join("") : ""}
        </div>
      `;
  }).join("");
  els.sampleList.innerHTML = renderPendingRows() + groupHtml;

  Array.from(els.sampleList.querySelectorAll(".sample-row:not(.pending)")).forEach((row) => {
    row.addEventListener("click", () => selectSample(row.dataset.sampleKey));
  });
  Array.from(els.sampleList.querySelectorAll(".sample-group-head")).forEach((head) => {
    head.addEventListener("click", () => {
      const prefix = head.dataset.group;
      if (state.openGroups.has(prefix)) state.openGroups.delete(prefix);
      else state.openGroups.add(prefix);
      renderSampleList();
    });
  });
}

function renderSampleList() {
  return runFeatureHook("renderSampleList", baseRenderSampleList, []);
}

function basename(value) {
  const text = String(value ?? "");
  const parts = text.split(/[\\/]/);
  return parts[parts.length - 1] ?? text;
}

function chartFullLabel(chart) {
  return basename(chart.source_file ?? chart.title ?? chart.display_name ?? chart.asset_key ?? "chart");
}

function selectedSample() {
  const sample = (state.library?.samples ?? []).find((item) => item.id === state.selectedKey);
  return sample ?? null;
}

function renderChartCard(chart, index) {
  const fullLabel = chartFullLabel(chart);
  return `
    <button type="button" class="chart-card" title="${escapeHtml(fullLabel)}" data-chart-index="${index}">
      <img loading="lazy" src="${escapeHtml(chart.url)}" alt="${escapeHtml(fullLabel)}" />
    </button>
  `;
}

function baseRenderChartsNav() {
  const samples = filteredSamples();
  const index = samples.findIndex((sample) => sample.id === state.selectedKey);
  const hasSamples = samples.length > 0 && index !== -1;

  els.chartNavPrev.disabled = !hasSamples || index <= 0;
  els.chartNavNext.disabled = !hasSamples || index >= samples.length - 1;
  els.chartNavPosition.textContent = hasSamples ? `${index + 1} of ${samples.length}` : "";
}

function renderChartsNav() {
  return runFeatureHook("renderChartsNav", baseRenderChartsNav, []);
}

function baseStepSelectedSample(delta) {
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

function stepSelectedSample(delta) {
  return runFeatureHook("stepSelectedSample", baseStepSelectedSample, [delta]);
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

function baseRenderMetadata() {
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

function renderMetadata() {
  return runFeatureHook("renderMetadata", baseRenderMetadata, []);
}

function baseReRender() {
  renderGlobalCounts();
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
  renderReport();
  // Header status is cleared on a routine successful load — it only speaks
  // up for "Loading..." and "Load failed" (principle 8: actionable only).
  els.status.textContent = "";
}

function reRender() {
  return runFeatureHook("reRender", baseReRender, []);
}

function selectSample(sampleKey) {
  state.selectedKey = sampleKey;
  const chosen = state.library?.samples?.find((sample) => sample.id === sampleKey);
  if (chosen) state.openGroups.add(batchPrefixOf(chosen));
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
  void loadSelectedSampleNote();
}

function baseAttachEvents() {
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

function attachEvents() {
  return runFeatureHook("attachEvents", baseAttachEvents, []);
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

// "Synced MM-DD HH:mm": when SpinLab last published anything (samples, charts or rules) to this site.
function renderSyncInfo() {
  const box = byId("sync-info");
  const when = new Date(state.report?.exportedAt);
  if (!box || Number.isNaN(when.getTime())) return;
  box.textContent = `Synced ${formatReadableTimestamp(state.report.exportedAt)}`;
  box.hidden = false;
}

// Follow SpinLab: when the published Synced time changes, load the new library and redraw,
// keeping the reader's filters, selected sample and opened groups.
async function refreshWhenSynced() {
  try {
    const response = await fetch("./data/export_report.json", { cache: "no-store" });
    if (!response.ok) return;
    const report = await response.json();
    if (!report?.exportedAt || report.exportedAt === state.report?.exportedAt) return;
    const libraryResponse = await fetch("./data/library.json", { cache: "no-store" });
    if (!libraryResponse.ok) return;
    state.library = await libraryResponse.json();
    state.report = report;
    const kept = [els.seriesFilter, els.batchFilter, els.assetFilter].map((select) => select.value);
    populateFilters();
    [els.seriesFilter, els.batchFilter, els.assetFilter].forEach((select, index) => {
      select.value = Array.from(select.options).some((option) => option.value === kept[index]) ? kept[index] : "all";
    });
    state.filters.series = els.seriesFilter.value;
    state.filters.batch = els.batchFilter.value;
    state.filters.assetGroup = els.assetFilter.value;
    let selectionChanged = false;
    if (!state.library.samples?.some((sample) => sample.id === state.selectedKey)) {
      state.selectedKey = state.library.samples?.[0]?.id ?? null;
      selectionChanged = true;
    }
    renderSyncInfo();
    reRender();
    // The old sample's note must not linger beside the new selection.
    if (selectionChanged) void loadSelectedSampleNote();
    void refreshPendingSamples();
  } catch {
    // Offline: keep showing what is already on the page.
  }
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
    renderSyncInfo();
    state.selectedKey = state.library.samples[0]?.id ?? null;
    populateFilters();
    attachEvents();
    reRender();
    void loadSelectedSampleNote();
    void refreshPendingSamples();
    setInterval(() => { void refreshWhenSynced(); void refreshPendingSamples(); }, 30000);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") { void refreshWhenSynced(); void refreshPendingSamples(); }
    });
  } catch (error) {
    els.status.textContent = "Load failed";
    els.metadataBody.innerHTML = `<div class="error"><strong>Unable to load export data.</strong><div class="muted">${escapeHtml(error.message)}</div></div>`;
  }
}

main();
