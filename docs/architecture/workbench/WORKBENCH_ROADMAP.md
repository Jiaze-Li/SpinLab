# Workbench — Shell Migration Roadmap

> Canonical phase progress and migration sequence for Workbench shell architecture.

## Purpose

This document is the single source of truth for Workbench shell migration phase status.

Use this file to track:

- completed phases
- current and upcoming phases
- completion criteria per phase

Detailed architecture contracts remain in sibling docs. This file tracks progress, not contract details.

## Completed Phases

| Phase | Scope | Status |
|---|---|---|
| Phase 3A | app bundle regression gates | complete |
| Phase 3B | web export chart asset regression tests | complete |
| Phase 4 | Plot Preservation Module | complete |
| Phase 5A | Search Module Contract + boundary tests | complete |
| Phase 5B | Main Board / Layout Host / Module / Module Group / Workflow Assembly architecture docs | complete |
| Phase 5C | Selection Module Contract + `WorkbenchSelectedHitsSnapshot` run-scoped read surface | complete |
| Phase 5D-1 | Analysis Lifecycle Module — boundary tests locking cross-module behavior | complete |
| Phase 5D-2 | Analysis Lifecycle Module — contract documentation | complete |
| Phase 5E-1 | Save Module — contract documentation | complete |
| Phase 5F-1 | Pack / Restore Module — audit (restore write map, boundary risks, legacy paths, test gaps) | complete |
| Phase 5F-2 | Pack / Restore Module — contract documentation | complete |

## Current and Next Phases

| Phase | Scope |
|---|---|
| Phase 5A-3 | Search Read Surface / mirror risk reduction |
| Phase 5D-3 | Analysis Lifecycle Module — shared runtime extraction (deferred; awaits stable contract + tests) |
| Phase 5E-2 | Save Module — boundary tests locking current save-boundary behavior |
| Phase 5E-3 | Save Module — saveMessage field extraction; refreshRelatedCharts gap fix in AHE; shared save coordinator (deferred until tests stable) |
| Phase 5F-3 | Pack / Restore Module — boundary tests (no-trace-commit, isAllSelected after restore, AHE legacy path) |
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
