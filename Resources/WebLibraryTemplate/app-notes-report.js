// Sample notes section, metadata panel helpers, and export report popover for the SpinLab Web Library.

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

function baseRenderMetadataPanel(sample) {
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

function renderMetadataPanel(sample) {
  return runFeatureHook("renderMetadataPanel", baseRenderMetadataPanel, [sample]);
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
