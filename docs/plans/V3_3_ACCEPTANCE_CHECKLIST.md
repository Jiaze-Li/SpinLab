# V3.3 Acceptance Checklist

Status: **DONE** (2026-04-05)
App version at closure: **v3.3.3.10**

---

## Stage Gate

| Criterion | Status | Evidence |
|-----------|--------|----------|
| `WorkbenchView.swift` contains zero workflow-specific (AHE) symbols | ✅ | grep returns 0 hits |
| `WorkbenchFeatureStore.swift` contains zero AHE-specific state or methods | ✅ | grep returns 0 hits |
| Adding RT/3W workspace requires only new View + Store + one registry line | ✅ | `WorkflowWorkspaceRegistry.swift` — commented RT/3W examples in place |
| All tests pass | ✅ | 237/237 (`swift test`, exit 0) |
| QA build passes and desktop `.app` produced | ✅ | `./scripts/build_desktop_app.sh debug` exit 0; `/Users/jack/Desktop/SpinLab.app` |
| App version bumped | ✅ | `v3.3.3.10` |

---

## Micro-iteration Delivery Record

### V3.3.0 — Shell Region Contract + Dispatch (2026-04-05)
Commit: `69af7cb`

- `WorkflowWorkspaceProvider` protocol defined
- `WorkflowWorkspaceRegistry` dispatch table created
- `WorkflowWorkspaceShell` two-column container added
- `AHEWorkspaceView` extracted from `WorkbenchView`
- `WorkbenchView` reduced to generic dispatch (69 lines, zero AHE symbols)
- Bundled V3.3.0–V3.3.2 into one commit (protocol, extraction, registry dispatch)

### V3.3.1 — AHEWorkspaceView Extraction
Delivered within V3.3.0 commit. `AHEWorkspaceView.swift` is a standalone file
conforming to `WorkflowWorkspaceProvider`.

### V3.3.2 — Generic Workspace Dispatch
Delivered within V3.3.0 commit. `WorkbenchView` delegates entirely to
`WorkflowWorkspaceRegistry`; zero AHE imports or branches remain.

### V3.3.3 — AHE State Isolation into AHEWorkspaceStore (2026-04-05)
Commit: `afb21f3`

- `AHEWorkspaceStore.swift` created (312 lines)
- All AHE-specific state and actions moved out of `WorkbenchFeatureStore`
- `WorkbenchFeatureStore` retains only: search query/results/running flag,
  route, section, workflow definitions/rules, archived records, project catalog
- `AHEWorkspaceView` subcomponents re-bound to `aheWorkspace`

### Test suite fixes (2026-04-05)
Commit: `8618e53`

- V321/V322: updated default axis expectations (Oe→T, Bridge1→R_H) per V3.3.3.8
- V324/V326: added distinct titles to same-second multi-run tests (timestamp filename scheme)
- V326/V327/V327V32: removed `chartIdentityKey`/`appVersion` from trace projection
  calls and assertions (removed from `WorkbenchRunTraceProjection` in `c92c0c7`)

### V330–V333 governance test files (2026-04-05)
`V330WorkbenchShellContractTests`, `V331AHEWorkspaceViewExtractionTests`,
`V332WorkflowWorkspaceDispatchTests`, `V333AHEWorkspaceStoreIsolationTests` added.
Test count at V3.3 closure: **237**.

---

## UX Iterations (V3.3.3.x, not in original scope)

| Version | Content |
|---------|---------|
| V3.3.3.8 | x-axis Magnetic Field (T), R_H (Ω) default y-axis, subscript rendering |
| V3.3.3.9 | Inline chart label editing, legend drag fix, font polish |

---

## Known Deferred Items

None. All V3.3 scope items are delivered and tested.
Next milestone: V3.4 (RT/3W workspace, or as directed).
