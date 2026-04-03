# SpinLab V3.1 Acceptance Checklist

Status: active
Owner: implementation + QA shared gate

This checklist is the acceptance gate for V3.1 only.

## Scope Boundary (must pass)

- [ ] V3.1 includes architecture skeleton + contracts only.
- [ ] No V3.2 pipeline/render features are required for V3.1 acceptance.
- [ ] No V3.3 Library read-model UI rollout is required for V3.1 acceptance.
- [ ] Cross-artifact all-or-nothing transaction rollback is tracked for V3.4, not V3.1.

## Contract and Schema (must pass)

- [ ] `PlotPayload` contract exists in code with version field.
- [ ] `MetricRecord` contract exists in code with sample-centric identity fields.
- [ ] `RunManifest` contract exists in code with traceability fields.
- [ ] Sample measurement data store contract exists (`records + latestIndex`).
- [ ] Condition alias config contract exists with explicit `schemaVersion`.

## Identity and Path (must pass)

- [ ] Chart identity key generation is deterministic on semantic inputs.
- [ ] Style-only changes do not alter chart identity key.
- [ ] Metric identity key generation normalizes condition key/value input.
- [ ] Relative-path persistence resolver exists and rejects root-escape input.

## Persistence Interface (must pass)

- [ ] Atomic write interface exists and is callable by downstream layers.
- [ ] Atomic write interface follows `temp-write -> fsync -> commit`.
- [ ] Atomic write overwrite path works for existing destination files.

## Failure Policy (must pass)

- [ ] Unknown condition-alias schema version fails explicitly (no silent fallback).
- [ ] Invalid alias JSON fails with explicit validation error.

## Tests (must pass)

- [ ] Round-trip serialization tests for V3.1 core contracts pass.
- [ ] Identity deterministic tests pass.
- [ ] Alias schema fail-fast tests pass.
- [ ] Path resolver round-trip + escape rejection tests pass.
- [ ] Atomic write behavior tests pass.

## Build and Runtime Gate (must pass)

- [ ] `swift test` passes.
- [ ] Desktop app build/overwrite completes for QA target.
- [ ] App version is bumped to current V3.1 iteration.

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
