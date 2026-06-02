# Workbench - Shell Migration Roadmap

> Canonical phase progress and migration sequence for Workbench shell architecture.

## Purpose

This document is the single source of truth for Workbench shell migration phase status.

Use this file to track:

- completed phases
- current and upcoming phases
- completion criteria per phase
- the current gate plan

Detailed architecture contracts remain in sibling docs. This file tracks progress, not contract details.

## Phase Taxonomy

Workbench modularization phases fall into three categories:

**Framework / Governance** — architecture language, routing rules, Workflow / Workflow Assembly / Main Board / Modules terminology, docs/index alignment.

**Boundary Stabilization** — module ownership contracts, forbidden mutations, transition read surfaces, regression gates, and guardrails.

**Runtime Extraction** — coordinator extraction and removal of duplicated workflow-local implementations.

5.3.7 completed the first two categories. The third category is post-5.3.7 work.

## Gate Plan

The current task is Gate 1.

| Gate | Status | Scope |
|---|---|---|
| Gate 1 | current | Record Architecture Decisions |
| Gate 2 | planned | Workflow Assembly Audit |
| Gate 3 | planned | Module Audit |
| Gate 4 | planned | Layout Audit |
| Gate 5 | planned | Layout Refactor |
| Gate 6 | planned | Readiness Consumption |
| Gate 7 | planned | Search Module Extraction |
| Gate 8 | planned | Selection Module Extraction |
| Gate 9 | planned | Analyze Module Extraction |
| Gate 10 | planned | Save / Pack Module Extraction |
| Gate 11 | planned | New Workflow Dry Run |

Gates 2 through 11 are planned future work. They are not completed by this documentation update.

## 5.3.7 Scope Closure

5.3.7 delivered the **Workbench modularization safety baseline**.

### Completed in 5.3.7

- Architecture language / governance baseline (Workflow, Workflow Assembly, Main Board, Modules terminology; docs/index alignment)
- Module boundary contracts for Search, Selection, Plot Preservation, Analysis Lifecycle, Save, Pack / Restore
- Transition read surfaces:
  - `WorkbenchSearchSnapshot`
  - `WorkbenchSelectedHitsSnapshot`
  - `saveMessage`
- Boundary regression gates for: Search, Selection, Plot Preservation, Analysis Lifecycle, Save, Pack / Restore, Workflow state
- App bundle and web export guardrails

Search Module read-surface extraction began in 5.3.7; runtime ownership cleanup remains post-5.3.7.
`WorkbenchReadinessProjection` has been implemented. Consumption by shell and result-header gating remains future work.

### Not completed in 5.3.7

- Full Main Board cleanup
- Full runtime module extraction
- Complete `cachedSearchResults` removal
- `SaveCoordinator` extraction
- `PackRestoreCoordinator` extraction
- `AnalysisLifecycleCoordinator` extraction
- Workflow Function Contract
- SOT workflow onboarding

## Completed Phases

| Phase | Scope | Status |
|---|---|---|
| Phase 3A | app bundle regression gates | complete |
| Phase 3B | web export chart asset regression tests | complete |
| Phase 4 | Plot Preservation Module | complete |
| Phase 5A | Search Module Contract + boundary tests | complete |
| Phase 5B | Workflow / Workflow Assembly / Main Board / Module / Module Group architecture docs | complete |
| Phase 5C | Selection Module Contract + `WorkbenchSelectedHitsSnapshot` run-scoped read surface | complete |
| Phase 5D-1 | Analysis Lifecycle Module — boundary tests locking cross-module behavior | complete |
| Phase 5D-2 | Analysis Lifecycle Module — contract documentation | complete |
| Phase 5E-1 | Save Module — contract documentation | complete |
| Phase 5E-2 | Save Module — boundary tests locking current save-boundary behavior | complete |
| Phase 5F-1 | Pack / Restore Module — audit (restore write map, boundary risks, legacy paths, test gaps) | complete |
| Phase 5F-2 | Pack / Restore Module — contract documentation | complete |
| Phase 5F-3 | Pack / Restore Module — boundary tests (no-trace-commit, isAllSelected after restore, AHE legacy path) | complete |

## Post-5.3.7 Phases

All phases below are post-5.3.7 runtime extraction work. None were in scope for the 5.3.7 safety baseline.

| Phase | Scope |
|---|---|
| Phase 5A-3 | Search Read Surface / mirror risk reduction (runtime ownership cleanup) |
| Phase 5D-3 | Analysis Lifecycle Module — shared runtime extraction (deferred; awaits stable contract + tests) |
| Phase 5E-3 | Save Module — saveMessage field + refreshRelatedCharts extraction into shared coordinator (deferred until contract stable) |
| Phase 5F-4 | Pack / Restore Module — implementation extraction (deferred; awaits stable contract + tests) |
| Phase 6 | Workflow Function Contract |
| Future | SOT workflow onboarding through shell framework |

## Completion Rule (Per Phase)

A phase is complete only when all checks pass:

1. Contract: target boundary/ownership contract is explicit in architecture docs.
2. Implementation: runtime behavior matches the contract.
3. Regression tests: contract has dedicated regression tests.
4. Docs/index updates: affected workbench docs and index links are updated.
5. Required action checks: repository action-gate checks are run and clean for the round scope.

## Cross-Links

- [Shell Blocks](SHELL_BLOCKS.md)
- [Extension Boundaries](EXTENSION_BOUNDARIES.md)
- [Module Boundaries](MODULE_BOUNDARIES.md)
