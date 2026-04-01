# Docs Index

## plans (what to build / execution and milestones)

| Document | Purpose | Status |
|---|---|---|
| `plans/V1_EXECUTION_PLAN.md` | V1 execution history and completion record. | done |
| `plans/V2_EXECUTION_PLAN.md` | V2 staged implementation plan and acceptance criteria. | active |
| `plans/APP_FLOW.md` | End-to-end app workflow and page responsibilities. | active |
| `plans/TECH_DEBT_EXECUTION_LOG.md` | Completed technical debt reduction rounds — dates, scope, rationale. | active |
| `plans/TECH_DEBT_BACKLOG.md` | Pending technical improvements that have been identified but not yet executed. | active |

## specs (how to build / constraints and standards)

| Document | Purpose | Status |
|---|---|---|
| `specs/00_RULES_INDEX.md` | Rules entry point and priority order. | active |
| `specs/01_PRODUCT_RULES.md` | Product behavior contract and safety boundaries. | active |
| `specs/02_DATA_RULES.md` | Domain model, metadata ownership, normalization rules. | active |
| `specs/03_PARSER_ROUTING_RULES.md` | Inbox parse/routing rules and conflict behavior. | active |
| `specs/04_UI_RULES.md` | UI layout and interaction rules. | active |
| `specs/05_INBOX_DEPOSIT_UI_SPEC.md` | Inbox deposit UI flow, button semantics, and drawer-mapping contract. | active |
| `specs/APP_DESIGN_PRINCIPLES.md` | Long-term architecture and product philosophy. | active |

## runtime rules (agent execution policy)

| Document | Purpose | Status |
|---|---|---|
| `../AGENTS.md` | Agent execution policy, hard gates, and implementation behavior constraints. | active |

## Notes
- Prefer adding new roadmap and milestone docs under `plans/`.
- Prefer adding new constraints/standards/domain contracts under `specs/`.
- Use status labels consistently: `active`, `draft`, `done`, `reference`.
- Legacy specs are kept under `docs/specs/archive/` as historical reference.
