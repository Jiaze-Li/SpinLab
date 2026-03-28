# Rule Schema Versioning

## Current status
- Runtime-supported schema version: `v1` (`RuleLoader.currentSchemaVersion`).
- Rules are loaded from `filename_rules.json`.
- Loader supports both:
  - legacy flat shape (`tokenization`, `sampleId`, `registry`, etc. at top-level)
  - namespaced shape (`shared`, `inbox`, `library`)

## Migration behavior
- If incoming schema version is **older** than supported:
  - loader applies compatibility migration mode
  - warns in load warnings
  - normalizes runtime metadata version to current supported version
- If incoming schema version is **newer** than supported:
  - loader keeps parsed payload in compatibility mode
  - warns in load warnings

## Evolution guidance
- `v1` -> `v2` changes should prefer additive fields first.
- For breaking changes:
  - add explicit migration path in `RuleLoader.migrateRuleSetSchemaIfNeeded`
  - add contract tests for both old and new payload shapes
