# Phone Write-Back Contract

This document defines the shared contract for the two phone write-back flows between the published Web Library (`SpinLab-Web-Library`) and the desktop `SpinLab` application:

1. **Phone New Sample Submission** (`/api/samples`)
2. **Sample Notes** (`/api/note`)

SpinLab owns the canonical field definitions, required-field rules, and desktop ingestion semantics. The live Cloudflare Pages Functions endpoints (`functions/api/samples.js`, `functions/api/note.js`) act as transport/storage queues and must remain compatible with this contract.

---

## 1. Ownership Matrix

| Layer / File | Repository | Role & Responsibility |
| --- | --- | --- |
| `Sources/SpinLabApp/config/new_sample_form_schema.json` | `SpinLab` | Single source of truth for required keys, numeric growth field keys/tags/units, and RHEED field keys/metadata keys. Bundled into `SpinLab.app` (`SpinLab_SpinLabApp.bundle` and `Contents/Resources/Publish/config/`). |
| `scripts/export_static_library.py` (`build_new_sample_form`) | `SpinLab` | Combines `new_sample_form_schema.json` with Rules Book option lists (`labs`, `growthMaterials`, `batchPrefixes`, `substrate.{treatments,defaultTreatment,materials,orientations}`) into `<web_repo>/public/data/new_sample_form.json`. |
| `Resources/WebLibraryTemplate/new-sample.js` | `SpinLab` | Renders the phone form from `data/new_sample_form.json`, collects raw user entries into `{ submission_id, fields }`, and submits `POST ./api/samples`. Performs no unit conversions. |
| `functions/api/samples.js` (Cloudflare D1 `pending_samples`) | `SpinLab-Web-Library` | Validates `submission_id` and `REQUIRED_TEXT_FIELDS`, stores pending JSON payloads (`POST /api/samples`), lists uncollected rows where `received_at IS NULL` (`GET /api/samples`), and marks rows received (`PUT /api/samples`). |
| `Sources/SpinLabApp/Library/NewSampleFields.swift` | `SpinLab` | Decodes `fields` from `GET /api/samples`, validates required fields and substrate choices, attaches units via `LibraryRegistryParser.numericDisplay`, and produces `CreateNativeSampleDraft`s. |
| `Sources/SpinLabApp/Library/PhoneSamplePickup.swift` | `SpinLab` | Polls `GET /api/samples` using the Cloudflare Access service token (`KeychainPhoneAccessTokenStore`), creates native samples atomically with deterministic `smp_<submission_id>` UIDs, and acknowledges via `PUT /api/samples`. |
| `Resources/WebLibraryTemplate/app.js` & `functions/api/note.js` | `SpinLab` / `SpinLab-Web-Library` | Reads (`GET /api/note?sample_id=...`) and updates (`PUT /api/note`) sample-scoped plain-text notes in Cloudflare D1 (`sample_notes`). |

---

## 2. Flow 1: Phone New Sample (`/api/samples`)

### 2.1 HTTP Endpoints (`functions/api/samples.js`)

- **`POST /api/samples`**
  - Request JSON:
    ```json
    {
      "submission_id": "<uuid-or-32-hex>",
      "fields": { ... }
    }
    ```
  - Server checks: `submission_id` is non-empty; `fields` is an object; every key in `REQUIRED_TEXT_FIELDS` (`batch`, `growthMaterial`, `substrateMaterial`, `substrateOrientation`) is a non-empty string.
  - Idempotency: `submission_id` is the primary key in `pending_samples` (resending the same `submission_id` updates/preserves the submission without duplicating samples).

- **`GET /api/samples`**
  - Returns `{ "submissions": [ { "submission_id": "...", "fields": { ... } }, ... ] }` for all rows with `received_at IS NULL`.

- **`PUT /api/samples`**
  - Request JSON: `{ "submission_id": "<id>" }`
  - Marks `received_at` in `pending_samples` only after `PhoneSamplePickup` has durably created all substrate drafts for that submission in the local SpinLab Library.

### 2.2 Canonical `fields` Payload Contract

All three SpinLab layers (`new_sample_form_schema.json`, `new-sample.js`, `NewSampleFields.swift`) must agree on the exact field names and types below:

#### Required Text Fields (`schema.required`)
| Key | Type | Description |
| --- | --- | --- |
| `batch` | `String` | Batch identifier (e.g. `PN117`). Required. |
| `growthMaterial` | `String` | Growth material from Rules Book `growthMaterialOptions`. Required. |
| `substrateMaterial` | `String` | First substrate material from Rules Book `substrate.materials`. Required. |
| `substrateOrientation` | `String` | First substrate orientation from Rules Book `substrate.orientations`. Required. |

#### Optional Text, Boolean & Structural Fields
| Key | Type | Description |
| --- | --- | --- |
| `date` | `String` | Growth date (`YYYY-MM-DD`, empty string if omitted). |
| `lab` | `String` | Lab name from Rules Book `labOptions` (empty string if omitted). |
| `substrateTreatment` | `String` | First substrate treatment (empty string uses `defaultTreatment`). |
| `extraSubstrates` | `[{ treatment, material, orientation }]` | Optional additional substrates grown in the same batch; each becomes a sample with UID `smp_<submission_id>-2`, `-3`, etc. |
| `hasAttenuator` | `Bool` | Whether the attenuator is in the beam path (`metadata["attenuator"] = "yes"` when true). |
| `purpose` | `String` | Sample purpose text (`metadata["purpose"]`). |
| `note` | `String` | Sample creation note (`metadata["note"]`). |
| `rheed` | `Object` | Nested RHEED numeric values keyed by `schema.rheedFields` (see below). |

#### Numeric Growth Fields (`schema.numberFields`)
Optional `Double` values on the top-level `fields` object:
| Key | Registry Tag (`tag`) | Unit (`unit`) |
| --- | --- | --- |
| `temperature` | `温度` | `°C` |
| `pressure` | `氧压` | `mT` |
| `sampleHeight` | `样品高度` | `mm` |
| `frontEnergy` | `镜前能量` | `mJ` |
| `laserVoltage` | `激光器电压` | `kV` |
| `laserOutputEnergy` | `激光器输出能量` | `mJ` |
| `prePulseCount` | `预打次数` | `` |
| `growthPulseCount` | `生长次数` | `` |
| `frequency` | `频率` | `Hz` |

#### RHEED Fields (`schema.rheedFields`)
Optional `Double` values inside `fields.rheed`:
| Key | Metadata Key (`metadataKey`) | Label |
| --- | --- | --- |
| `grid` | `RHEED Grid` | `Grid` |
| `focus` | `RHEED Focus` | `Focus` |
| `x1` | `RHEED X1` | `X1` |
| `y1` | `RHEED Y1` | `Y1` |
| `y2` | `RHEED Y2` | `Y2` |
| `x2` | `RHEED X2` | `X2` |

---

## 3. Flow 2: Sample Notes (`/api/note`)

- **`GET /api/note?sample_id=<id>`**
  - Returns `{ "sample_id": "<id>", "note_text": "<string>", "updated_at": "<iso8601-or-null>" }`.
- **`PUT /api/note`**
  - Request JSON: `{ "sample_id": "<id>", "note_text": "<string>" }`.
  - Response JSON: `{ "sample_id": "<id>", "note_text": "<string>", "updated_at": "<iso8601>" }`.
- **Storage boundary:** Stored in Cloudflare D1 table `sample_notes(sample_id TEXT PRIMARY KEY, note_text TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)`. Never written into `public/data/library.json` or the local SpinLab Library files.

---

## 4. Automated Consistency Check

`scripts/tests/test_phone_writeback_contract.py` enforces field parity across:
1. `Sources/SpinLabApp/config/new_sample_form_schema.json`
2. `Sources/SpinLabApp/Library/NewSampleFields.swift`
3. `Resources/WebLibraryTemplate/new-sample.js`
4. `Resources/WebLibraryTemplate/app.js` (note API contract)

Any field addition, rename, or removal that is not synchronized across the schema, Swift model, and phone script fails the test suite.
