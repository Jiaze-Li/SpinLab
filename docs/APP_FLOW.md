# SpinLab App Flow

## Core V1 Flow

SpinLab V1 uses one workflow only:

- `Import -> Confirm -> Visualize -> Analyze -> Save -> Archive`

This workflow is defined for `AMR/PHE` measurements only.

## 1. Import

- User selects or drops local `AMR/PHE` files into `Inbox`
- App creates a pending import item
- The pending item stores source file reference and basic file metadata
- Imported items are not archived automatically

## 2. Confirm

- SpinLab parses filename-derived hints for:
  - `Batch`
  - `Sample`
  - `Measurement`
  - optional `Device`
- Parsed values are suggestions only
- `Project` is not assumed from filename
- User reviews and corrects metadata in the confirmation form
- Once a sample is matched, SpinLab may suggest `Project` from existing links
- User can select or create a `Project` during confirmation
- Confirmation creates or links:
  - `Batch`
  - `Sample`
  - optional `Device`
  - `Project`
  - `Measurement`
  - `Dataset`
- `Measurement.measurement_type` is set explicitly to `AMR/PHE`

## 3. Visualize

- User opens the confirmed measurement in `Workbench`
- `Workbench` loads the linked dataset
- V1 supports the default raw plotting path only
- Plotting behavior is limited to `AMR/PHE` measurements

## 4. Analyze

- V1 analysis is intentionally minimal
- User can review raw curves and enter simple notes or derived values
- Analysis output is represented through `Result`

## 5. Save

- Save creates or updates a `Result` attached to the active `Measurement`
- Save does not flatten result data directly onto the archived measurement record
- The latest result remains associated with the measurement for later review

## 6. Archive

- Only explicitly confirmed items enter the archive
- Archived measurements become visible in `Library`
- `Library` is the canonical persisted source of truth
- Reopening from `Library` loads the archived `Measurement`, its `Dataset`, and any saved `Result`

## Page Roles

### Inbox

- Entry point for import
- Displays pending items and confirmation state
- Hosts metadata confirmation before archival

### Workbench

- Focused single-measurement workspace
- Shows metadata and raw plots
- Saves or updates measurement-linked results

### Library

- Browses archived measurements
- Supports primary V1 filters:
  - `Project`
  - `Sample`
  - `Batch`
  - `measurement_type`
  - date
- Rating is not a primary V1 filter
- Drawer structure and sync model follow the Library interaction contract:
  - App view hierarchy: `Library -> Prefix -> Batch -> Drawer`
  - Physical hierarchy: `batches/<prefix>/<batchId>/samples/<sampleKey>`
  - `Sync Registry` means align app drawer tags/metadata toward XLSX target (detect first, then manual apply)
  - `Sync File` means align app state toward current filesystem reality (manual trigger refresh)
  - `Apply All` applies all pending registry operations in queue
  - `Apply Selected` applies pending registry operations for selected batch only
  - Pending queue is an operation queue, not a generic browser:
    - green `+`: add
    - red `-`: remove
    - yellow marker: change
