function compareOverviewOrderStable() {
  return [...state.compare.groups].sort((left, right) => left.number - right.number);
}

compareOverviewOrder = compareOverviewOrderStable;

renderCompareOverview = function renderCompareOverviewStable(sample) {
  if (state.compare.mode !== "compare") {
    return "";
  }

  const groups = compareOverviewOrderStable();
  return `
    <div class="detail-section compare-overview">
      <div class="detail-section-head">
        <div class="section-title">Compare overview</div>
        <div class="muted compare-overview-count">${groups.length} groups found</div>
      </div>
      ${groups.length
        ? `<div class="compare-overview-scroll-shell">
            <div class="compare-overview-list" tabindex="0" aria-label="Comparison groups">
              ${groups
                .map((group) => {
                  const contains = group.samples.some((item) => item.id === sample.id);
                  const selected = group.id === state.compare.selectedGroupKey;
                  return `
                    <button
                      type="button"
                      class="compare-overview-card${selected ? " selected" : ""}"
                      data-compare-group="${escapeHtml(group.id)}"
                      ${selected ? 'aria-current="true"' : ""}
                    >
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
            </div>
          </div>`
        : `<div class="muted">No controlled groups match these settings.</div>`}
    </div>
  `;
};

const spinlabCompareOverviewBaseRenderMetadata = renderMetadata;
let spinlabCompareOverviewScrollTop = 0;

renderMetadata = function renderMetadataWithStableCompareScroll() {
  const currentScroller = els.metadataBody?.querySelector(".compare-overview-list");
  if (currentScroller) {
    spinlabCompareOverviewScrollTop = currentScroller.scrollTop;
  }

  spinlabCompareOverviewBaseRenderMetadata();

  const nextScroller = els.metadataBody?.querySelector(".compare-overview-list");
  if (nextScroller) {
    nextScroller.scrollTop = spinlabCompareOverviewScrollTop;
  }
};
