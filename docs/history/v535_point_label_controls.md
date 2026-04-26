# v5.3.5 — Point Label Controls + Copy PNG Scale Menu

## What shipped

Three independent features implemented across C1 (Claude), C2 (Codex), C3 (Claude).

### C1 — Point Label Font Size
- `WorkbenchChartStyle.pointLabelFontSize` field (default 20); parsed from `styleParams["pointLabelFontSize"]`
- Renderer reads `style.pointLabelFontSize` instead of hardcoded 20
- `EditTarget.pointLabel` added to canvas hit-test flow; tapping a label opens font-size edit panel
- `chartStyleOverrides` persisted in `ThreeOmegaPackConfig` (top-level field, shared across tabs; backward-compat decode defaults to `[:]`)

### C2 — Point Label Visibility Toggle + Pack Persistence
- `TabRenderState.hiddenPointLabelIndicesBySeries: [Int: [Int]]` — Codable [Int:[Int]] for Pack, [Int:Set<Int>] at runtime
- `TabRenderManager`: `togglePointLabelVisibility(seriesIndex:pointIndex:)` + `hiddenPointLabelSet(for:)` helpers
- `WorkbenchRenderPipeline.Input.hiddenPointLabelsBySeries` forwarded to renderer; renderer skips suppressed labels
- `WorkbenchPlotLayout`: computes `pointDotHitTargets` + `pointLabelHitTargets` only when payload carries pointLabels (payload-capability gate)
- Canvas: `EditTarget.pointDot` dispatches toggle on dot tap; `EditTarget.pointLabel` dispatches font-size edit on label tap
- `WorkbenchPlottingStore`: `togglePointLabelVisibility` protocol method + no-op default
- `WorkflowWorkspaceShell`: wires `onTogglePointLabelVisibility`
- Persistence: flows through `tabStates` in `ThreeOmegaPackConfig` (automatic)

### C3 — Copy PNG 1x/2x/3x Scale Menu
- `WorkbenchRenderPipeline.Input.pixelScaleOverride: CGFloat?` — overrides `baseOptions.pixelScale` when set
- `WorkbenchPlottingStore`: `renderPNGAtScale(_ scale: CGFloat) -> Data?` + nil-returning default
- `ThreeOmegaWorkspaceStore`: 2x fast path returns `activeImageData` directly; 1x/3x re-render via pipeline with scale override
- Canvas: `copyPNGScales: [CGFloat] = [1, 2, 3]` static; `onCopyPNG` callback; contextMenu replaced with `Menu("Copy PNG") > 3 items`
- Shell: wires `onCopyPNG: { scale in store.renderPNGAtScale(scale) }`

## Architecture notes
- `chartStyleOverrides` is shared across tabs (not per-tab) — Pack field is top-level, not in `tabStates`. If per-tab font sizes are needed in future, `TabRenderState` is the right home.
- The payload-capability gate (`hasPointLabels`) ensures zero hit-test overhead for non-scatter tabs.
- 2x fast path is an exact equality check (`scale == 2.0`) relying on the literal `2.0` in `WorkbenchChartRenderer.Options.pixelScale` default — deterministic as long as the default doesn't change.

## Tests
- `V535PointLabelVisibilityTests` — toggle reversibility, multi-series isolation
- `V535TabRenderStatePackTests` — Codable roundtrip, missing-field backward compat
- `V535ScopeGateTests` — payload-capability gate, hit-target count
- `V535CopyPNGScaleMenuTests` — scale array alignment, output pixel width = baseWidth × scale, 2x determinism
