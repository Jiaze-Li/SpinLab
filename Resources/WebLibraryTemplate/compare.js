const COMPARE_MIN_GROUP_SIZE = 4;

const COMPARE_DIMENSIONS = [
  { key: "material", label: "Material", type: "text" },
  { key: "substrate", label: "Substrate", type: "text" },
  { key: "energy", label: "Energy", type: "number", tag: "能量", unit: "mJ" },
  { key: "oxygen", label: "O₂", type: "number", tag: "氧压", unit: "mT" },
  { key: "temperature", label: "Temperature", type: "number", tag: "温度", unit: "°C" },
  { key: "thickness", label: "Thickness", type: "number", tag: "厚度", unit: "ps" },
];

state.compare = {
  mode: "samples",
  allowed: {
    material: false,
    substrate: false,
    energy: true,
    oxygen: false,
    temperature: false,
    thickness: false,
  },
  groups: [],
  records: new Map(),
  selectedGroupKey: null,
  scannedCount: 0,
  excludedCount: 0,
};

const spinlabBaseRenderMetadataPanel = renderMetadataPanel;
const spinlabBaseAttachEvents = attachEvents;
const spinlabBaseReRender = reRender;

function compareNormalizeText(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ");
}

function compareMaterialValue(sample) {
  const raw = sample.metadata?.["靶"] ?? sample.metadata?.target ?? sample.metadata?.material ?? "";
  const display = compareNormalizeText(raw);
  if (!display) {
    return null;
  }
  return {
    key: display.toUpperCase(),
    display,
    sort: display.toUpperCase(),
  };
}

function compareSubstrateValue(sample) {
  const display = compareNormalizeText(sample.substrateDisplay ?? "");
  if (!display) {
    return null;
  }
  const tokens = Array.isArray(sample.substrateTokens)
    ? sample.substrateTokens.map(compareNormalizeText).filter(Boolean)
    : [];
  const canonical = tokens.length ? tokens.join("|") : display;
  return {
    key: canonical.toUpperCase(),
    display,
    sort: canonical.toUpperCase(),
  };
}

function compareNumericValue(sample, dimension) {
  const raw = sample.numericTags?.[dimension.tag];
  const value = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isFinite(value)) {
    return null;
  }
  return {
    key: value,
    display: `${value.toLocaleString()} ${dimension.unit}`,
    sort: value,
  };
}

function compareDimensionValue(sample, dimension) {
  if (dimension.key === "material") {
    return compareMaterialValue(sample);
  }
  if (dimension.key === "substrate") {
    return compareSubstrateValue(sample);
  }
  return compareNumericValue(sample, dimension);
}

function buildCompareRecord(sample) {
  const values = {};
  for (const dimension of COMPARE_DIMENSIONS) {
    const value = compareDimensionValue(sample, dimension);
    if (!value) {
      return null;
    }
    values[dimension.key] = value;
  }
  return { sample, values };
}

function compareAllowedDimensions() {
  return COMPARE_DIMENSIONS.filter((dimension) => state.compare.allowed[dimension.key]);
}

function compareStrictDimensions() {
  return COMPARE_DIMENSIONS.filter((dimension) => !state.compare.allowed[dimension.key]);
}

function compareRecordSort(left, right) {
  for (const dimension of compareAllowedDimensions()) {
    const a = left.values[dimension.key].sort;
    const b = right.values[dimension.key].sort;
    if (dimension.type === "number") {
      if (a !== b) {
        return a - b;
      }
    } else {
      const result = naturalCompare(a, b);
      if (result !== 0) {
        return result;
      }
    }
  }
  return compareSamples(left.sample, right.sample);
}

function rebuildCompareGroups() {
  const samples = state.library?.samples ?? [];
  const strictDimensions = compareStrictDimensions();
  const records = new Map();
  const buckets = new Map();
  let excludedCount = 0;

  for (const sample of samples) {
    const record = buildCompareRecord(sample);
    if (!record) {
      excludedCount += 1;
      continue;
    }
    records.set(sample.id, record);
    const keyParts = strictDimensions.map((dimension) => record.values[dimension.key].key);
    const key = JSON.stringify(keyParts);
    if (!buckets.has(key)) {
      buckets.set(key, []);
    }
    buckets.get(key).push(record);
  }

  const groups = Array.from(buckets.entries())
    .filter(([, groupRecords]) => groupRecords.length >= COMPARE_MIN_GROUP_SIZE)
    .map(([key, groupRecords]) => ({
      key,
      records: groupRecords.sort(compareRecordSort),
    }))
    .sort((left, right) => {
      if (right.records.length !== left.records.length) {
        return right.records.length - left.records.length;
      }
      const leftSample = left.records[0]?.sample;
      const rightSample = right.records[0]?.sample;
      return leftSample && rightSample ? compareSamples(leftSample, rightSample) : 0;
    })
    .map((group, index) => ({
      ...group,
      id: `group-${index + 1}`,
      number: index + 1,
      samples: group.records.map((record) => record.sample),
    }));

  state.compare.records = records;
  state.compare.groups = groups;
  state.compare.scannedCount = samples.length;
  state.compare.excludedCount = excludedCount;

  if (state.compare.selectedGroupKey && !groups.some((group) => group.id === state.compare.selectedGroupKey)) {
    state.compare.selectedGroupKey = null;
  }
}

function selectedCompareGroup() {
  return state.compare.groups.find((group) => group.id === state.compare.selectedGroupKey) ?? null;
}

function compareDistinctValues(group, dimension) {
  const distinct = new Map();
  for (const record of group.records) {
    const value = record.values[dimension.key];
    if (!distinct.has(String(value.key))) {
      distinct.set(String(value.key), value);
    }
  }
  return Array.from(distinct.values()).sort((left, right) => {
    if (dimension.type === "number") {
      return left.sort - right.sort;
    }
    return naturalCompare(left.sort, right.sort);
  });
}

function compareValueList(group, dimension, limit = 8) {
  const values = compareDistinctValues(group, dimension);
  const shown = values.slice(0, limit).map((value) => value.display);
  if (values.length > limit) {
    shown.push(`+${values.length - limit} more`);
  }
  return shown.join(" · ");
}

function compareFixedSummary(group) {
  const strictDimensions = compareStrictDimensions();
  if (strictDimensions.length === 0) {
    return "No strict-match variables";
  }
  const record = group.records[0];
  return strictDimensions.map((dimension) => record.values[dimension.key].display).join(" · ");
}

function compareStrictLabel() {
  const labels = compareStrictDimensions().map((dimension) => dimension.label);
  return labels.length ? labels.join(" · ") : "None";
}

function compareVariationRows(group, compact = false) {
  const allowed = compareAllowedDimensions();
  if (allowed.length === 0) {
    return `<div class="compare-replicate-note">Replicates: all comparison variables are identical.</div>`;
  }
  const limit = compact ? 5 : 10;
  return allowed
    .map((dimension) => {
      const values = compareDistinctValues(group, dimension);
      return `
        <div class="compare-variation-row">
          <span class="compare-variation-label">${escapeHtml(dimension.label)}</span>
          <span class="compare-variation-values">${escapeHtml(compareValueList(group, dimension, limit))}</span>
          <span class="compare-level-count">${values.length} value${values.length === 1 ? "" : "s"}</span>
        </div>
      `;
    })
    .join("");
}

function compareSampleValueSummary(sample) {
  const record = state.compare.records.get(sample.id);
  if (!record) {
    return "";
  }
  const allowed = compareAllowedDimensions();
  if (allowed.length === 0) {
    return "replicate";
  }
  return allowed.map((dimension) => record.values[dimension.key].display).join(" · ");
}

function ensureCompareUI() {
  const panel = els.sampleList?.closest(".samples-panel");
  if (!panel || panel.querySelector("#library-mode-tabs")) {
    return;
  }

  const panelHead = panel.querySelector(".panel-head");
  const searchField = els.search.closest(".search-field");

  const tabs = document.createElement("div");
  tabs.id = "library-mode-tabs";
  tabs.className = "library-mode-tabs";
  tabs.innerHTML = `
    <button type="button" class="library-mode-tab active" data-library-mode="samples">Samples</button>
    <button type="button" class="library-mode-tab" data-library-mode="compare">Compare</button>
  `;
  panel.insertBefore(tabs, panelHead);

  const controls = document.createElement("div");
  controls.id = "compare-controls";
  controls.className = "compare-controls";
  controls.hidden = true;
  controls.innerHTML = `
    <div class="compare-control-head">
      <strong>Allow to differ</strong>
      <span class="compare-min-note">groups ≥ ${COMPARE_MIN_GROUP_SIZE}</span>
    </div>
    <div class="compare-checkbox-grid">
      ${COMPARE_DIMENSIONS.map(
        (dimension) => `
          <label class="compare-checkbox">
            <input type="checkbox" data-compare-dimension="${escapeHtml(dimension.key)}" ${state.compare.allowed[dimension.key] ? "checked" : ""} />
            <span>${escapeHtml(dimension.label)}</span>
          </label>
        `,
      ).join("")}
    </div>
    <div class="compare-strict-line">Strict match: <span id="compare-strict-values"></span></div>
    <div id="compare-scan-status" class="compare-scan-status"></div>
    <div id="compare-selection-summary" class="compare-selection-summary"></div>
  `;
  panel.insertBefore(controls, searchField);
}

function syncCompareChrome() {
  ensureCompareUI();
  const panel = els.sampleList.closest(".samples-panel");
  const isCompare = state.compare.mode === "compare";
  const panelTitle = panel.querySelector(".panel-head h2");
  const controls = panel.querySelector("#compare-controls");
  const searchField = els.search.closest(".search-field");
  const filtersRow = els.seriesFilter.closest(".filters-row");

  panel.querySelectorAll("[data-library-mode]").forEach((button) => {
    const active = button.dataset.libraryMode === state.compare.mode;
    button.classList.toggle("active", active);
    button.setAttribute("aria-pressed", String(active));
  });

  panelTitle.textContent = isCompare ? "Compare" : "Samples";
  controls.hidden = !isCompare;
  searchField.hidden = isCompare;
  filtersRow.hidden = isCompare;

  if (!isCompare) {
    els.sampleList.classList.remove("compare-group-list");
    els.sampleList.setAttribute("aria-label", "sample list");
    return;
  }

  panel.querySelector("#compare-strict-values").textContent = compareStrictLabel();
  const excluded = state.compare.excludedCount;
  panel.querySelector("#compare-scan-status").textContent =
    `${state.compare.scannedCount} scanned · ${state.compare.groups.length} groups found` +
    (excluded ? ` · ${excluded} incomplete excluded` : "");

  const group = selectedCompareGroup();
  const selection = panel.querySelector("#compare-selection-summary");
  if (!group) {
    selection.innerHTML = "";
    return;
  }

  selection.innerHTML = `
    <button type="button" class="compare-back-button" data-compare-action="all-groups">← All groups</button>
    <div class="compare-selected-title">Group ${group.number} · ${group.samples.length} samples</div>
    <div class="compare-fixed-label">Fixed</div>
    <div class="compare-fixed-values">${escapeHtml(compareFixedSummary(group))}</div>
    <div class="compare-selected-variations">${compareVariationRows(group, true)}</div>
  `;
}

function renderCompareGroupList() {
  const groups = state.compare.groups;
  els.tableCount.textContent = `${groups.length} groups`;
  els.sampleList.classList.add("compare-group-list");
  els.sampleList.setAttribute("aria-label", "controlled comparison groups");

  if (groups.length === 0) {
    els.sampleList.innerHTML = `
      <div class="compare-empty">
        <strong>No groups found.</strong>
        <div class="muted">Change the variables allowed to differ. Every returned group must contain at least ${COMPARE_MIN_GROUP_SIZE} complete samples.</div>
      </div>
    `;
    return;
  }

  els.sampleList.innerHTML = groups
    .map(
      (group) => `
        <button type="button" class="compare-group-card" data-compare-group="${escapeHtml(group.id)}">
          <span class="compare-group-card-head">
            <strong>Group ${group.number} · ${group.samples.length} samples</strong>
            <span aria-hidden="true">›</span>
          </span>
          <span class="compare-group-fixed">${escapeHtml(compareFixedSummary(group))}</span>
          <div class="compare-group-variations">${compareVariationRows(group, true)}</div>
        </button>
      `,
    )
    .join("");
}

function renderCompareGroupSamples(group) {
  els.tableCount.textContent = `${group.samples.length} samples`;
  els.sampleList.classList.remove("compare-group-list");
  els.sampleList.setAttribute("aria-label", `Group ${group.number} samples`);
  els.sampleList.innerHTML = group.samples
    .map((sample) => {
      const selected = sample.id === state.selectedKey;
      return `
        <div class="sample-row${selected ? " selected" : ""}" data-compare-sample-key="${escapeHtml(sample.id)}" role="option" aria-selected="${selected}">
          <span class="sample-row-name">${escapeHtml(sample.displayName)}</span>
          <span class="compare-sample-values">${escapeHtml(compareSampleValueSummary(sample))}</span>
        </div>
      `;
    })
    .join("");
}

renderSampleList = function renderSampleListWithCompare() {
  syncCompareChrome();
  if (state.compare.mode !== "compare") {
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
    return;
  }

  const group = selectedCompareGroup();
  if (group) {
    renderCompareGroupSamples(group);
  } else {
    renderCompareGroupList();
  }
};

function compareNavigationSamples() {
  if (state.compare.mode === "compare") {
    const group = selectedCompareGroup();
    if (group) {
      return group.samples;
    }
  }
  return filteredSamples();
}

function scrollSelectedSampleIntoView() {
  window.requestAnimationFrame(() => {
    const row = els.sampleList?.querySelector('.sample-row.selected');
    row?.scrollIntoView({ block: "nearest" });
  });
}

function stepVisibleSample(delta) {
  const samples = compareNavigationSamples();
  if (!samples.length) {
    return false;
  }
  let index = samples.findIndex((sample) => sample.id === state.selectedKey);
  if (index === -1) {
    index = delta > 0 ? -1 : samples.length;
  }
  const nextIndex = index + delta;
  if (nextIndex < 0 || nextIndex >= samples.length) {
    return false;
  }
  selectSample(samples[nextIndex].id);
  scrollSelectedSampleIntoView();
  return true;
}

renderChartsNav = function renderChartsNavWithCompare() {
  const samples = compareNavigationSamples();
  const index = samples.findIndex((sample) => sample.id === state.selectedKey);
  const hasSamples = samples.length > 0 && index !== -1;
  els.chartNavPrev.disabled = !hasSamples || index <= 0;
  els.chartNavNext.disabled = !hasSamples || index >= samples.length - 1;
  els.chartNavPosition.textContent = hasSamples ? `${index + 1} of ${samples.length}` : "";
};

stepSelectedSample = function stepSelectedSampleWithCompare(delta) {
  stepVisibleSample(delta);
};

function compareOverviewOrder(sample) {
  const selectedKey = state.compare.selectedGroupKey;
  return [...state.compare.groups].sort((left, right) => {
    const leftSelected = left.id === selectedKey ? 1 : 0;
    const rightSelected = right.id === selectedKey ? 1 : 0;
    if (leftSelected !== rightSelected) {
      return rightSelected - leftSelected;
    }
    const leftContains = left.samples.some((item) => item.id === sample.id) ? 1 : 0;
    const rightContains = right.samples.some((item) => item.id === sample.id) ? 1 : 0;
    if (leftContains !== rightContains) {
      return rightContains - leftContains;
    }
    return left.number - right.number;
  });
}

function renderCompareOverview(sample) {
  if (state.compare.mode !== "compare") {
    return "";
  }
  const groups = state.compare.groups;
  const orderedGroups = compareOverviewOrder(sample);
  return `
    <div class="detail-section compare-overview">
      <div class="detail-section-head">
        <div class="section-title">Compare overview</div>
        <div class="muted compare-overview-count">${groups.length} groups found</div>
      </div>
      ${orderedGroups.length
        ? `<div class="compare-overview-list" style="max-height: 260px; overflow-y: auto; overscroll-behavior: contain; padding-right: 3px;">
            ${orderedGroups
              .map((group) => {
                const contains = group.samples.some((item) => item.id === sample.id);
                const selected = group.id === state.compare.selectedGroupKey;
                return `
                  <button type="button" class="compare-overview-card${selected ? " selected" : ""}" data-compare-group="${escapeHtml(group.id)}">
                    <span class="compare-overview-card-head">
                      <strong>Group ${group.number} · ${group.samples.length} samples</strong>
                      <span aria-hidden="true">›</span>
                    </span>
                    <span class="compare-overview-fixed">${escapeHtml(compareFixedSummary(group))}</span>
                    ${contains ? `<span class="compare-current-chip">Current sample</span>` : ""}
                  </button>
                `;
              })
              .join("")}
          </div>`
        : `<div class="muted">No controlled groups match these settings.</div>`}
    </div>
  `;
}

renderMetadataPanel = function renderMetadataPanelWithCompare(sample) {
  const ordered = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata
    : Object.entries(sample.metadata ?? {}).map(([key, value]) => ({ key, value }));
  const numericEntries = Object.entries(sample.numericDisplay ?? {}).filter(([, value]) => !isEmptyMetadataValue(value));
  const additionalMetadata = ordered.filter(
    (item) => !isDuplicateMetadataKey(item.key) && !isEmptyMetadataValue(item.value),
  );
  return `
    ${renderIdentityBlock(sample)}
    ${renderCompareOverview(sample)}
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
};

function setCompareMode(mode) {
  if (mode !== "samples" && mode !== "compare") {
    return;
  }
  state.compare.mode = mode;
  if (mode === "compare") {
    rebuildCompareGroups();
  }
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
}

function selectCompareGroup(groupId) {
  const group = state.compare.groups.find((item) => item.id === groupId);
  if (!group) {
    return;
  }
  state.compare.mode = "compare";
  state.compare.selectedGroupKey = group.id;
  const currentInGroup = group.samples.some((sample) => sample.id === state.selectedKey);
  const nextSample = currentInGroup ? state.selectedKey : group.samples[0]?.id;
  if (nextSample && nextSample !== state.selectedKey) {
    selectSample(nextSample);
    scrollSelectedSampleIntoView();
    return;
  }
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
  scrollSelectedSampleIntoView();
}

function showAllCompareGroups() {
  state.compare.mode = "compare";
  state.compare.selectedGroupKey = null;
  renderSampleList();
  renderMetadata();
  renderChartsPanel();
  window.requestAnimationFrame(() => {
    els.sampleList?.scrollTo({ top: 0 });
  });
}

function isKeyboardNavigationEditable(target) {
  return target instanceof HTMLElement &&
    (target.tagName === "INPUT" ||
      target.tagName === "TEXTAREA" ||
      target.tagName === "SELECT" ||
      target.isContentEditable);
}

function handleVerticalSampleNavigation(event) {
  if (event.defaultPrevented || event.altKey || event.metaKey || event.ctrlKey || event.shiftKey) {
    return;
  }
  if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
    return;
  }
  if (state.lightbox.open || isKeyboardNavigationEditable(event.target)) {
    return;
  }
  if (state.compare.mode === "compare" && !selectedCompareGroup()) {
    return;
  }
  const moved = stepVisibleSample(event.key === "ArrowDown" ? 1 : -1);
  if (moved) {
    event.preventDefault();
  }
}

function handleCompareActionClick(event) {
  const groupButton = event.target.closest?.("[data-compare-group]");
  if (groupButton) {
    event.preventDefault();
    selectCompareGroup(groupButton.dataset.compareGroup);
    return true;
  }
  const action = event.target.closest?.("[data-compare-action]");
  if (action?.dataset.compareAction === "all-groups") {
    event.preventDefault();
    showAllCompareGroups();
    return true;
  }
  return false;
}

attachEvents = function attachEventsWithCompare() {
  spinlabBaseAttachEvents();
  ensureCompareUI();
  const panel = els.sampleList.closest(".samples-panel");

  panel.addEventListener("click", (event) => {
    const modeButton = event.target.closest("[data-library-mode]");
    if (modeButton) {
      setCompareMode(modeButton.dataset.libraryMode);
      return;
    }

    if (handleCompareActionClick(event)) {
      return;
    }

    const sampleRow = event.target.closest("[data-compare-sample-key]");
    if (sampleRow) {
      selectSample(sampleRow.dataset.compareSampleKey);
      scrollSelectedSampleIntoView();
    }
  });

  panel.addEventListener("change", (event) => {
    const checkbox = event.target.closest("[data-compare-dimension]");
    if (!checkbox) {
      return;
    }
    state.compare.allowed[checkbox.dataset.compareDimension] = checkbox.checked;
    state.compare.selectedGroupKey = null;
    rebuildCompareGroups();
    renderSampleList();
    renderMetadata();
    renderChartsPanel();
  });

  els.metadataBody.addEventListener("click", (event) => {
    handleCompareActionClick(event);
  });

  document.addEventListener("keydown", handleVerticalSampleNavigation);
};

reRender = function reRenderWithCompare() {
  ensureCompareUI();
  if (state.compare.mode === "compare") {
    rebuildCompareGroups();
  }
  spinlabBaseReRender();
  syncCompareChrome();
};
