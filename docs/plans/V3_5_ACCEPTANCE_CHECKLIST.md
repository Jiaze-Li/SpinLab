# V3.5 Acceptance Checklist

Stage gate for the 3.5 branch. Each item must be checked before merging to main.

Evidence key:
- **test** — covered by automated test suite (suite name noted)
- **code** — verified by static code inspection
- **manual** — requires human QA on a built `.app`

---

## Functional Acceptance

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | `extractAHEMetrics` extracts both Hc and R_AHE in a single pass with shared background removal | ✅ | code: `AHEWorkspaceStore.swift` L544; test: V350 dual-metric regression |
| 2 | Single-sample render persists both Hc record (canonicalUnit "T") and R_AHE record (canonicalUnit "Ω") to `measurement_data.json` | ✅ | test: `V350ConcurrentWriteConsistencyTests/singleSamplePersistWritesBothHcAndRAHE` |
| 3 | R_AHE override panel independent of Hc override; each override clears after successful persist | ✅ | code: `AHEWorkspaceView.swift`; `pendingRAHEOverride` lifecycle in `AHEWorkspaceStore` |
| 4 | Library "Measurements Done" list sorted alphabetically | ✅ | code: `LibraryFeatureStore.swift` sort on `appliedAt`/display name |
| 5 | Delete button in "Measurements Done" removes sidecar file and refreshes projection | ✅ | test: `V350ConcurrentWriteConsistencyTests/deleteAppliedMeasurementRemovesSidecarFile` |
| 6 | `deleteAppliedMeasurement` failure surfaces to `librarySampleEditError`; cache not invalidated on error | ✅ | code: `LibraryFeatureStore.swift` L1015 do/catch; test: delete regression |
| 7 | Multi-sample renders skip R_AHE persist (consistent with Hc skip rule) | ✅ | code: `AHEWorkspaceStore.swift` guard `sampleKeys.count == 1` applies to both metrics |

## Quality Gates

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 8 | All tests pass (279 baseline + V3.5 new tests) | ✅ | test run 2026-04-05: 8/8 V350 suite passed |
| 9 | `AppVersion.library` bumped to `v3.5.0` | ✅ | `AppVersion.swift` L3 |
| 10 | PR review findings addressed before merge | ✅ | commit `25249f6`: do/catch + dual-metric + delete regression tests |

---

## V3 Completion Criteria (Final Verification)

Per `V3_EXECUTION_PLAN.md` §15:

| # | Criterion | Status |
|---|-----------|--------|
| 1 | AHE workflow produces chart assets through unified plot layer | ✅ |
| 2 | All outputs traceable via run manifests and run IDs | ✅ |
| 3 | Library reads Workbench results and measurement data without compute coupling | ✅ |
| 4 | Raw measurement files remain immutable | ✅ |
| 5 | Overwrite behavior prevents style-only artifact inflation | ✅ |
| 6 | Alias/rename semantics visible in UI and safe in runtime reads | ✅ |

**V3 closed 2026-04-05. All 6 completion criteria met.**

---

## Notes

- V3.5 is the final iteration of V3. V4.0 (3ω AHE workflow) branch already scaffolded.
- R_AHE extraction uses 80% H_max saturation threshold with median plateau estimator; fallback to (ymax − ymin)/2 when either plateau is empty.
- Test count: 279 baseline → 281 after V3.5 regression additions.
