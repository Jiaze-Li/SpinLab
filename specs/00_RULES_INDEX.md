# SpinLab Rules Index

Status: active

This file is the entry point for all active implementation rules.

## Rule priority
1. `specs/01_PRODUCT_RULES.md`
2. `specs/02_DATA_RULES.md`
3. `specs/03_PARSER_ROUTING_RULES.md`
4. `specs/04_UI_RULES.md`
5. `specs/06_PROJECT_ARCHITECTURE.md`

If two rules conflict, the higher-priority file above wins.

## Scope of each rule doc
- `01_PRODUCT_RULES.md`: product behavior contract and Definition of Done boundaries.
- `02_DATA_RULES.md`: domain objects, metadata schema, normalization, and persistence ownership.
- `03_PARSER_ROUTING_RULES.md`: parse/routing logic contract for Inbox -> Library.
- `04_UI_RULES.md`: layout and interaction rules only.
- `06_PROJECT_ARCHITECTURE.md`: SpinLab-specific code placement, canonical implementations, module contracts, change boundaries, build policy, and pre-merge checklist.

Long-term product/architecture philosophy lives in `docs/philosophy.md` (developer philosophy) and is not duplicated here.

## Domain knowledge (non-rule reference)
- `three_omega_physics.md`: 3ω AHE measurement physics derivations. Reference for `ThreeOmegaFitUseCase` / `ThreeOmegaScalingUseCase` correctness review.

## Archived specs
Historical docs are moved under `specs/archive/` and are reference-only. Notable archives:
- `APP_DESIGN_PRINCIPLES_LEGACY.md` — folded into `docs/philosophy.md` + 01/02/06.
- `INBOX_DEPOSIT_UI_LEGACY.md` — Inbox UI design doc; rules folded into 01/03/04 + `docs/features.md`.
