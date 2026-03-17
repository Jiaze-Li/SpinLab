# SpinLab V1 Implementation Plan

## Phase 1: Canonical Model And Workflow Contract

- Finalize V1 identities and relationships for:
  - `Project`
  - `Batch`
  - `Sample`
  - `Device`
  - `Measurement`
  - `Dataset`
  - `Result`
  - `Comparison`
- Make `measurement_type` an explicit core field on `Measurement`
- Lock the only V1 workflow to `AMR/PHE`
- Define pending, confirmed, and archived lifecycle states
- Define archive gating rules so confirmation is required

## Phase 2: Inbox And Filename Parsing

- Build file import into `Inbox`
- Create a pending queue for imported files
- Implement filename parsing for:
  - `Batch`
  - `Sample`
  - `Measurement`
  - optional `Device`
- Keep parser output editable and non-authoritative
- Do not treat `Project` as a first-class filename hint

## Phase 3: Confirmation And Linking

- Build confirmation UI for matching or creating canonical objects
- Allow linking or creating:
  - `Batch`
  - `Sample`
  - optional `Device`
  - `Project`
  - `Measurement`
- Suggest `Project` from existing sample links where possible
- Set `Measurement.measurement_type` explicitly to `AMR/PHE`
- Enforce explicit confirmation before archival

## Phase 4: Archive Persistence

- Persist canonical `Measurement`, `Dataset`, and linked objects into archive storage
- Preserve source traceability to imported files
- Ensure archived measurements can be reopened without relinking

## Phase 5: Workbench

- Load archived `AMR/PHE` dataset structure
- Render raw plots through the default plotting path only
- Support one measurement at a time in `Workbench`
- Create or update a `Result` attached to the active `Measurement`

## Phase 6: Library

- Add archived measurement list and detail browsing
- Support primary V1 filters:
  - `Project`
  - `Sample`
  - `Batch`
  - `measurement_type`
  - date
- Do not treat rating as a primary V1 filter
- Allow reopening archived measurements in `Workbench`

## Phase 7: Extension Seams And Hardening

- Extract lightweight interfaces for:
  - parser
  - `AMR/PHE` workflow
  - plotting
  - analysis entry points
- Add tests for parsing, confirmation gating, result persistence, and archive reload behavior

## Post-V1 Work

- Additional workflows:
  - `MR`
  - `RT`
  - `AHE`
  - `Harmonic`
- Advanced analysis pipelines
- Rich comparison UI
- Rating-based discovery
- Multi-dataset measurements
- Collaboration and sync
