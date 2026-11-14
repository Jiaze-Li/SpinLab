// Phone page: fill in one new sample and send it to the cloud queue SpinLab collects from.
// Choices (lab, materials, substrate) come from data/new_sample_form.json, exported from the Rules Book.
// This page only collects raw numbers; SpinLab converts them and adds units when it receives the sample.
// The unit shown next to a number is a label only and must match SpinLab's unit table
// (a SpinLab test compares the two).

const NUMBER_FIELDS = [
  { key: "temperature", label: "Temperature", unit: "°C" },
  { key: "pressure", label: "Pressure", unit: "mT" },
  { key: "sampleHeight", label: "Sample height", unit: "mm" },
  { key: "frontEnergy", label: "Front energy", unit: "mJ" },
  { key: "laserVoltage", label: "Laser voltage", unit: "kV" },
  { key: "laserOutputEnergy", label: "Laser output energy", unit: "mJ" },
  { key: "prePulseCount", label: "Pre-ablation pulses", unit: "" },
  { key: "growthPulseCount", label: "Growth pulses", unit: "" },
  { key: "frequency", label: "Frequency", unit: "Hz", placeholder: "2" },
];

const RHEED_FIELDS = [
  { key: "grid", label: "Grid" },
  { key: "focus", label: "Focus" },
  { key: "x1", label: "X1" },
  { key: "y1", label: "Y1" },
  { key: "y2", label: "Y2" },
  { key: "x2", label: "X2" },
];

const els = {};
const state = { form: null, submissionId: null, submitted: false, sending: false };

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

// Fixed when the page opens (and again only for "New another"), so every resend is the same submission.
function makeSubmissionId() {
  if (window.crypto && typeof window.crypto.randomUUID === "function") {
    return window.crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  window.crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function todayString() {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}

function selectHtml(id, label, options, { required = false, blankLabel = "Select" } = {}) {
  const optionHtml = options.map((name) => `<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`).join("");
  return `
    <label class="field">
      <span class="field-label">${escapeHtml(label)}${required ? " *" : ""}</span>
      <select id="${id}"><option value="">${escapeHtml(blankLabel)}</option>${optionHtml}</select>
    </label>`;
}

function numberHtml(field, prefix = "num") {
  const unit = field.unit ? `<span class="field-unit">${escapeHtml(field.unit)}</span>` : "";
  return `
    <label class="field">
      <span class="field-label">${escapeHtml(field.label)}</span>
      <span class="field-input">
        <input id="${prefix}-${field.key}" type="text" inputmode="decimal" placeholder="${escapeHtml(field.placeholder ?? "")}" />
        ${unit}
      </span>
    </label>`;
}

function renderForm() {
  const form = state.form;
  els.fields.innerHTML = `
    <label class="field">
      <span class="field-label">Date</span>
      <input id="date" type="date" value="${todayString()}" />
    </label>
    ${selectHtml("lab", "Lab", form.labs, { blankLabel: "None" })}
    ${selectHtml("growthMaterial", "Material", form.growthMaterials, { required: true })}
    <label class="field">
      <span class="field-label">Batch *</span>
      <input id="batch" type="text" autocapitalize="characters" placeholder="e.g. PN200" />
    </label>
    <fieldset class="field-group">
      <legend>Substrate</legend>
      ${selectHtml("substrateTreatment", "Treatment", form.substrate.treatments, { blankLabel: "Default" })}
      ${selectHtml("substrateMaterial", "Material", form.substrate.materials, { required: true })}
      ${selectHtml("substrateOrientation", "Orientation", form.substrate.orientations, { required: true })}
    </fieldset>
    <fieldset class="field-group">
      <legend>Growth</legend>
      ${NUMBER_FIELDS.map((field) => numberHtml(field)).join("")}
      <label class="field field-check">
        <input id="hasAttenuator" type="checkbox" />
        <span class="field-label">Attenuator in the beam path</span>
      </label>
    </fieldset>
    <label class="field">
      <span class="field-label">Purpose</span>
      <input id="purpose" type="text" />
    </label>
    <label class="field">
      <span class="field-label">Note</span>
      <input id="note" type="text" />
    </label>
    <details class="field-group">
      <summary>RHEED</summary>
      ${RHEED_FIELDS.map((field) => numberHtml(field, "rheed")).join("")}
    </details>`;
}

function textValue(id) {
  return byId(id).value.trim();
}

// Empty means "not given". Anything else must be a plain number.
function numberValue(id, label) {
  const text = textValue(id);
  if (text === "") {
    return { value: null };
  }
  const value = Number(text);
  if (!Number.isFinite(value)) {
    return { error: `${label} needs a number, for example 250.` };
  }
  return { value };
}

function collectFields() {
  const fields = {
    date: textValue("date"),
    lab: textValue("lab"),
    growthMaterial: textValue("growthMaterial"),
    batch: textValue("batch"),
    substrateTreatment: textValue("substrateTreatment"),
    substrateMaterial: textValue("substrateMaterial"),
    substrateOrientation: textValue("substrateOrientation"),
    hasAttenuator: byId("hasAttenuator").checked,
    purpose: textValue("purpose"),
    note: textValue("note"),
    rheed: {},
  };
  const missing = [];
  if (!fields.batch) missing.push("Batch");
  if (!fields.growthMaterial) missing.push("Material");
  if (!fields.substrateMaterial) missing.push("Substrate material");
  if (!fields.substrateOrientation) missing.push("Substrate orientation");
  if (missing.length > 0) {
    return { error: `${missing.join(", ")} required.` };
  }
  for (const field of NUMBER_FIELDS) {
    const result = numberValue(`num-${field.key}`, field.label);
    if (result.error) return { error: result.error };
    if (result.value !== null) fields[field.key] = result.value;
  }
  for (const field of RHEED_FIELDS) {
    const result = numberValue(`rheed-${field.key}`, `RHEED ${field.label}`);
    if (result.error) return { error: result.error };
    if (result.value !== null) fields.rheed[field.key] = result.value;
  }
  return { fields };
}

function setStatus(kind, text) {
  els.status.className = `submit-status ${kind}`;
  els.status.textContent = text;
}

async function submit(event) {
  event.preventDefault();
  if (state.sending) return;
  const collected = collectFields();
  if (collected.error) {
    setStatus("error", `Not submitted. ${collected.error}`);
    return;
  }
  state.sending = true;
  els.submit.disabled = true;
  setStatus("pending", "Submitting…");
  try {
    const response = await fetch("./api/samples", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ submission_id: state.submissionId, fields: collected.fields }),
    });
    if (!response.ok) {
      throw new Error(`Server answered ${response.status}`);
    }
    state.submitted = true;
    els.another.hidden = false;
    setStatus("ok", "Submitted");
  } catch (error) {
    // The form keeps everything that was typed; tapping Submit again resends the same submission.
    setStatus("error", "Not submitted. Your entries are still here — tap Submit again when you have signal.");
  } finally {
    state.sending = false;
    els.submit.disabled = false;
  }
}

function startAnother() {
  state.submissionId = makeSubmissionId();
  state.submitted = false;
  els.another.hidden = true;
  setStatus("", "");
  renderForm();
}

async function main() {
  els.fields = byId("form-fields");
  els.status = byId("submit-status");
  els.submit = byId("submit-button");
  els.another = byId("another-button");
  state.submissionId = makeSubmissionId();
  try {
    const response = await fetch("./data/new_sample_form.json");
    if (!response.ok) throw new Error(`Failed to load form options (${response.status})`);
    state.form = await response.json();
  } catch (error) {
    setStatus("error", "Could not load the form options. Reload the page.");
    els.submit.disabled = true;
    return;
  }
  renderForm();
  byId("sample-form").addEventListener("submit", submit);
  els.another.addEventListener("click", startAnother);
}

main();
