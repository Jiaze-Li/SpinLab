# Stage 3 — Baseline and Remaining Debt Closeout

## Closed point

- Branch: gate8.5A
- Commit: 94a11f7 fix(3omega): default renderer workflow identity
- App: /Applications/SpinLab.app
- Version: v5.5.4
- CFBundleVersion: 202606280855
- check_required_actions.sh: No rebuild or publish required

---

## Stage 3A — ThreeOmega workflowID baseline failure

**Result: fixed.**

ThreeOmegaPlotRenderer defaulted workflowID to `""`. Store paths overwrote it at runtime, but direct renderer paths emitted a blank workflowID. Fixed by defaulting the renderer workflowID to `"3w"` in production code. ThreeOmegaRAHEVsDeviceManifestTests baseline failure cleared.

**Classification:** Production bug fix.

---

## Stage 3B — IV x-axis migration policy audit

**Result: document and defer.**

IV current-axis labels migrated from A units to mA units. Migration correctly upgrades old auto labels and preserves non-matching custom labels. The only theoretical lossy case is a user label that exactly matched an auto label — indistinguishable without provenance metadata. Properly fixing this would require `xLabelIsUserAuthored` tracking and pack migration complexity not warranted now.

**Classification:** Compatibility debt, behaviorally safe.  
**Decision:** No code change.

---

## Stage 3C — AHE title hybrid audit

**Result: document and defer.**

AHE resolves `titleOverride` before payload construction, so `displayPayload.title` can already contain the user title. The render pipeline applies `titleOverride` again from `TabRenderState`. This is structurally redundant but behaviorally safe because `titleOverride` is overwrite-idempotent. Copy PNG, screen render, pack restore, and source identity all remain correct. Future cleanup: pass template-resolved base title as `payload.title` and let the pipeline apply `titleOverride` as the sole display override path, during an AHE render refactor.

**Classification:** Harmless hybrid / design debt.  
**Decision:** No code change.

---

## Stage 3D — PointTag physical location audit

**Result: document and defer.**

Two PointTag helpers are physically under `Workbench/V3/` despite belonging semantically to PlotSystem/Preservation:

- `Workbench/V3/WorkbenchPointTagState.swift`
- `Workbench/V3/TabRenderManager+PointTags.swift`

Single-target layout means the location has no compile, import, or dependency impact. No user-visible bug, no pack issue, no test failure. Include in a future V3 → PlotSystem relocation batch.

**Classification:** Architecture / documentation debt only.  
**Decision:** No standalone move.

---

## Final Stage 3 status

- Known baseline failure (3A) cleared.
- No active correctness bug identified in 3B–3D audits.
- Remaining items are low-risk design debt, documented above.
- Do not reopen Stage 3 unless a user-visible bug surfaces.

---

## Remaining future backlog

- AHE title policy cleanup — during a future AHE render refactor.
- IV label provenance metadata — only if TabRenderState schema changes for another reason.
- V3 → PlotSystem relocation batch, including PointTag files.
- Long-term PlotSystem API hardening.
