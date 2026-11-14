state.compare.scopeSignature = "";

function compareScopeSignature() {
  return JSON.stringify({
    search: state.filters.search.trim(),
    series: state.filters.series,
    batch: state.filters.batch,
    assetGroup: state.filters.assetGroup,
    chartsOnly: state.filters.chartsOnly,
    allowed: COMPARE_DIMENSIONS.filter((dimension) => state.compare.allowed[dimension.key]).map(
      (dimension) => dimension.key,
    ),
  });
}

function compareScopedSamples() {
  return filteredSamples();
}

rebuildCompareGroups = function rebuildCompareGroupsWithinScope() {
  const signature = compareScopeSignature();
  const scopeChanged = signature !== state.compare.scopeSignature;
  if (scopeChanged) {
    state.compare.scopeSignature = signature;
    state.compare.selectedGroupKey = null;
    if (typeof spinlabCompareOverviewScrollTop !== "undefined") {
      spinlabCompareOverviewScrollTop = 0;
    }
  }

  const samples = compareScopedSamples();
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
};

const spinlabCompareScopeBaseSyncChrome = syncCompareChrome;

syncCompareChrome = function syncCompareChromeWithScope() {
  spinlabCompareScopeBaseSyncChrome();

  const panel = els.sampleList.closest(".samples-panel");
  const isCompare = state.compare.mode === "compare";
  const searchField = els.search.closest(".search-field");
  const filtersRow = els.seriesFilter.closest(".filters-row");

  searchField.hidden = false;
  filtersRow.hidden = false;
  els.search.placeholder = "Search samples: sto111 20mt 120mj";

  if (!isCompare) {
    return;
  }

  panel.querySelector(".compare-back-button")?.remove();
  const status = panel.querySelector("#compare-scan-status");
  if (status) {
    status.textContent =
      `${state.compare.scannedCount} matched · ${state.compare.groups.length} groups found` +
      (state.compare.excludedCount ? ` · ${state.compare.excludedCount} incomplete excluded` : "");
  }
};

renderCompareGroupList = function renderCompareGroupSelectionHint() {
  const groups = state.compare.groups;
  els.tableCount.textContent = `${groups.length} groups`;
  els.sampleList.classList.remove("compare-group-list");
  els.sampleList.setAttribute("aria-label", "comparison group selection");

  if (groups.length === 0) {
    els.sampleList.innerHTML = `
      <div class="compare-empty">
        <strong>No groups found.</strong>
        <div class="muted">Adjust the search, filters, or variables allowed to differ.</div>
      </div>
    `;
    return;
  }

  els.sampleList.innerHTML = `
    <div class="compare-empty">
      <strong>Select a group on the right.</strong>
      <div class="muted">The Compare overview is the group navigator; this panel will show the selected group's samples.</div>
    </div>
  `;
};

const spinlabCompareScopeBaseAttachEvents = attachEvents;

attachEvents = function attachEventsWithSharedSampleFilters() {
  spinlabCompareScopeBaseAttachEvents();

  function refreshCompareFromSharedFilters() {
    if (state.compare.mode !== "compare") {
      return;
    }
    rebuildCompareGroups();
    renderSampleList();
    renderMetadata();
    renderChartsPanel();
  }

  els.search.addEventListener("input", refreshCompareFromSharedFilters);
  els.seriesFilter.addEventListener("change", refreshCompareFromSharedFilters);
  els.batchFilter.addEventListener("change", refreshCompareFromSharedFilters);
  els.assetFilter.addEventListener("change", refreshCompareFromSharedFilters);
  els.chartOnly.addEventListener("change", refreshCompareFromSharedFilters);
};
