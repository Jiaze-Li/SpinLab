# SpinLab Rules Index

Status: active

This file is the entry point for all active implementation rules.

## Rule priority
1. `docs/specs/01_PRODUCT_RULES.md`
2. `docs/specs/02_DATA_RULES.md`
3. `docs/specs/03_PARSER_ROUTING_RULES.md`
4. `docs/specs/04_UI_RULES.md`
5. `docs/specs/APP_DESIGN_PRINCIPLES.md`

If two rules conflict, the higher-priority file above wins.

## Scope of each rule doc
- `01_PRODUCT_RULES.md`: product behavior contract and Definition of Done boundaries.
- `02_DATA_RULES.md`: domain objects, metadata schema, normalization, and persistence ownership.
- `03_PARSER_ROUTING_RULES.md`: parse/routing logic contract for Inbox -> Library.
- `04_UI_RULES.md`: layout and interaction rules only.
- `APP_DESIGN_PRINCIPLES.md`: long-term philosophy and architectural direction.

## Archived specs
Historical docs are moved under `docs/specs/archive/` and are reference-only.
