# V3.4 Acceptance Checklist

Stage gate for the 3.4.0 branch. Each item must be checked before merging to main.

Evidence key:
- **test** — covered by automated test suite (suite name noted)
- **code** — verified by static code inspection
- **manual** — requires human QA on a built `.app`

---

## Functional Acceptance

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | `PersistMeasurementDataUseCase` writes `measurement_data.json` via `AtomicFileWriter` | ✅ | test: V340; code: `AHEWorkspaceStore.swift` uses `AtomicFileWriter()` |
| 2 | Manual override captured pre-persist; `overrideInfo` populated correctly | ✅ | test: V341 |
| 3 | `LoadWorkbenchResultsUseCase` + `LibraryFeatureStore` projection operational | ✅ | test: V342 |
| 4 | `LoadMeasurementDataUseCase` + `LibraryFeatureStore` projection operational | ✅ | test: V343 |
| 5 | Library "Workbench Results" section renders chart references (read-only) | ⬜ | manual |
| 6 | Library "Measurement Data" section renders latest values (read-only) | ⬜ | manual |
| 7 | Override marker `*` shown for overridden values only | ⬜ | manual |
| 8 | `WorkbenchMetricOverrideInfo` includes `source: OverrideSource` (Adj-7) | ✅ | test: V341 |
| 9 | Alias badge shown when `ConditionAliasBook` present; plain key when absent | ⬜ | manual |
| 10 | Condition keys into `makeIdentityKey` are canonical, not alias keys (Adj-8) | ✅ | test: V340, V341 |
| 11 | "Show" button opens the exact referenced PNG, not always latest (Adj-9) | ⬜ | manual |
| 12 | Corrupt/truncated JSON returns nil in all read use cases; no crash (Adj-10) | ✅ | test: V343 |
| 13 | No JSON reads in `LibraryView.swift` or any Library subview (Adj-5) | ✅ | code: grep confirms zero hits |
| 14 | All new write paths use `AtomicFileWriter`; no raw `Data.write` to Library paths | ✅ | code: inspection of `AHEWorkspaceStore`, `LibraryFeatureStore` |

## Quality Gates

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 15 | All tests pass (237 baseline + V3.4 new tests) | ✅ | 279/279 passed (2026-04-05) |
| 16 | `AppVersion` bumped to v3.4.x | ✅ | `AppVersion.library = "v3.4.3"` |
| 17 | `build_desktop_app.sh debug` passes | ⬜ | manual |
| 18 | QA Desktop `.app` produced and smoke-tested | ⬜ | manual |

---

## Notes

- Items 5, 6, 7, 9, 11, 17, 18 require a built macOS `.app` to verify. These must be
  signed off by a human reviewer before merge to main.
- Test count grew from the 237 baseline to 279 (42 new tests added across V340–V343 plus
  the LibraryDialogsModifier refactor commit).
