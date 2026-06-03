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
| Gate 1 | current | Record Architecture Decisions / Finalize Gate Plan |
| Gate 2 | complete | Workflow Assembly Audit & Contract Validation |
| Gate 3 | planned | Module Audit & Contract Validation |
| Gate 4 | planned | Layout Audit |
| Gate 5 | planned | Layout Refactor |
| Gate 6 | planned | Readiness Consumption |
| Gate 7 | planned | Module Extraction Program |
| Gate 8 | planned | New Workflow Dry Run |

Gate 1 remains current for this roadmap-finalization PR. Gate 2 is complete via PR #96. Gates 3 through 8 are planned future work. Gate 7 is a container gate. Its extraction sequence is determined after Gate 3.

### Gate 2 - Workflow Assembly Audit & Contract Validation

Reference:

- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)

Purpose:

- Audit current AHE / XY Rotation / 3ω workflows
- Extract actual workflow assemblies
- Validate the Assembly Contract

Clarify:

If real workflows cannot be described cleanly by the current contract:

- Update `WORKFLOW_ASSEMBLY.md`

Do not force workflows into an incorrect contract.

Acceptance:

- Every workflow has an Assembly Record
- Every Assembly Record maps to real implementation files
- Every Assembly Record explains how the workflow operates
- Assembly Contract has no obvious missing sections
- Assembly Contract has no known invalid assumptions

Result:

- Assembly Contract v1.0
- Completed via PR #96 (`docs: record workflow assembly mappings`)

### Gate 3 - Module Audit & Contract Validation

Reference:

- [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md)

Purpose:

- Determine actual module inventory
- Validate module ownership rules
- Validate module boundaries

Clarify:

If current modules contradict the contract:

- Update `MODULE_BOUNDARIES.md`

Do not force modules into an incorrect contract.

Examples of rules to validate:

- ownership
- canonical state
- capability boundaries
- read surfaces
- forbidden mutation
- sibling isolation

Acceptance:

- Actual module inventory identified
- Ownership defined
- State ownership defined
- Capability ownership defined
- Known exceptions documented
- Contract updated if necessary

Result:

- Module Contract v1.0
- Module Inventory v1.0

### Gate 4 - Layout Audit

Purpose:

- Validate current `WorkflowWorkspaceShell` layout
- Distinguish Layout vs Module vs Assembly Contribution

### Gate 5 - Layout Refactor

Purpose:

- Refactor layout only
- No behavior changes

### Gate 6 - Readiness Consumption

Purpose:

- Connect `WorkbenchReadinessProjection` to:
  - button gating
  - status display
  - preflight checks

### Gate 7 - Module Extraction Program

Important:

- Gate 7 is a container gate.
- Do not hardcode specific modules here.
- The actual extraction sequence will be determined after Gate 3.

### Gate 7.1+ - Tentative Examples Only

These are placeholders.

- Search Extraction
- Selection Extraction
- Analyze Lifecycle Extraction
- Save Extraction
- Pack Extraction
- Plot Extraction
- Trace / Warning / Status Extraction

Clarify:

Gate 3 may:

- merge modules
- split modules
- change extraction order
- redefine boundaries
- remove planned extraction steps

Do not present 7.1+ as fixed.

### Gate 8 - New Workflow Dry Run

Purpose:

- Validate the architecture

Acceptance:

- Create a new workflow (for example SOT)
- The workflow should be added primarily through a new Workflow Assembly
- Verify that Main Board does not require modification
- Verify that Layout does not require modification
- Verify that existing Modules do not require modification
- Document any remaining friction points

Result:

- New workflow onboarding remains assembly-led

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
