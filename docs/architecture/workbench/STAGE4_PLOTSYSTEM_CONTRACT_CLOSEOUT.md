# Stage 4 — PlotSystem Contract Closeout

## Closed point
- Branch: `gate8.5A`
- Commit: `d152af6 fix(plotsystem): keep manifest title display-clean`
- App: `/Applications/SpinLab.app`
- Version: `v5.5.4`
- `CFBundleVersion`: `202606281259`
- `check_required_actions.sh`: No rebuild or publish required

## Stage 4A — PlotSystem API contract audit
Result: audit completed.

Summary:
- `WorkbenchPlotExportService` correctly renders from `displayPayload` plus `TabRenderState`.
- ThreeOmega `manifestPayload` is clean because it uses `_refreshManifestPayloads()`.
- IV and AHE used `WorkbenchRenderPipeline.Output.manifestPayload` directly.
- Audit found that pipeline `manifestPayload` restored `axisMapping` but not `title`.
- Therefore `titleOverride` could leak into IV/AHE `manifestPayload.title`.
- RSM remains outside the standard `ExportService` path and was recorded as out of scope.
- XYRotation manifest/display sharing remains structural debt but was not part of this fix.

Classification:
- Contract gap with low current behavioral risk.

## Stage 4B — Contract characterization tests
Result: tests added.

Summary:
- Added IV manifest title characterization tests.
- Added AHE manifest title characterization tests.
- Added Copy PNG idempotence smoke tests.
- Tests confirmed:
  - `displayPayload.title` remained scientific/template title.
  - `manifestPayload.title` received user `titleOverride` for IV/AHE.
  - Copy PNG export was idempotent across tested scales and states.

Classification:
- Test-driven contract confirmation.

## Stage 4C — `manifestPayload` title cleanup
Result: fixed.

Summary:
- `WorkbenchRenderPipeline` now captures `originalTitle` before applying display overrides.
- When building `manifestPayload`, it restores both:
  - `manifestPayload.title = originalTitle`
  - `manifestPayload.axisMapping = originalAxisMapping`
- IV/AHE tests were converted from characterization assertions to contract assertions.
- `manifestPayload.title` no longer leaks user `titleOverride`.
- Visible render behavior and Copy PNG/export behavior remain unchanged.
- Pack schema unchanged.

Classification:
- Production contract fix.

## Final Stage 4 status
- `manifestPayload` is now display-override-clean for axis mapping and title.
- Export path remains `displayPayload` plus `TabRenderState`.
- Copy PNG idempotence is covered by regression tests.
- No active Stage 4 correctness bug remains.

## Remaining future backlog
- XYRotation manifest/display shared-payload design decision.
- RSM export path documentation or future standardization.
- Future `WorkbenchRenderPipeline.Output` API hardening if needed.
- Long-term V3 → PlotSystem relocation batch.
- Possible AHE title policy simplification during future AHE render refactor.
