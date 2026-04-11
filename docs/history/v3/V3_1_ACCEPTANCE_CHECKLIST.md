# SpinLab V3.1 Acceptance Checklist

Status: done (accepted on 2026-04-03)
Owner: implementation + QA shared gate

This checklist is the acceptance gate for V3.1 only.

## Scope Boundary (must pass)

- [x] V3.1 includes architecture skeleton + contracts only.
- [x] No V3.2 pipeline/render features are required for V3.1 acceptance.
- [x] No V3.3 Library read-model UI rollout is required for V3.1 acceptance.
- [x] Cross-artifact all-or-nothing transaction rollback is tracked for V3.4, not V3.1.

## Contract and Schema (must pass)

- [x] `PlotPayload` contract exists in code with version field.
- [x] `MetricRecord` contract exists in code with sample-centric identity fields.
- [x] `RunManifest` contract exists in code with traceability fields.
- [x] Sample measurement data store contract exists (`records + latestIndex`).
- [x] Condition alias config contract exists with explicit `schemaVersion`.

## Identity and Path (must pass)

- [x] Chart identity key generation is deterministic on semantic inputs.
- [x] Style-only changes do not alter chart identity key.
- [x] Metric identity key generation normalizes condition key/value input.
- [x] Relative-path persistence resolver exists and rejects root-escape input.

## Persistence Interface (must pass)

- [x] Atomic write interface exists and is callable by downstream layers.
- [x] Atomic write interface follows `temp-write -> fsync -> commit`.
- [x] Atomic write overwrite path works for existing destination files.

## Failure Policy (must pass)

- [x] Unknown condition-alias schema version fails explicitly (no silent fallback).
- [x] Invalid alias JSON fails with explicit validation error.

## Tests (must pass)

- [x] Round-trip serialization tests for V3.1 core contracts pass.
- [x] Identity deterministic tests pass.
- [x] Alias schema fail-fast tests pass.
- [x] Path resolver round-trip + escape rejection tests pass.
- [x] Atomic write behavior tests pass.

## Build and Runtime Gate (must pass)

- [x] `swift test` passes.
- [x] Desktop app build/overwrite completes for QA target.
- [x] App version is bumped to current V3.1 iteration.

## Evidence (current implementation snapshot)

- Contracts:
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchResultContracts.swift`
- Identity:
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchArtifactIdentity.swift`
- Alias loader:
  - `Sources/SpinLabApp/Workbench/V3/ConditionAliasConfig.swift`
  - `Sources/SpinLabApp/config/condition_aliases.json`
- Path resolver:
  - `Sources/SpinLabApp/Library/LibraryPathResolver.swift`
- Atomic write interface:
  - `Sources/SpinLabApp/Storage/AtomicFileWriter.swift`
- Tests:
  - `Tests/SpinLabAppTests/V310WorkbenchFoundationTests.swift`
