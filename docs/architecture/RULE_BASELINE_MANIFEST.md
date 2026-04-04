# Rule Baseline Manifest

Status: active  
Last updated: 2026-04-04

## Purpose

This manifest is the single baseline for:
- where rules come from,
- which precedence is applied at runtime,
- which code-level interpretation logic is not configurable in JSON,
- and which tests lock behavior against drift.

This document is intentionally explicit so rule-file changes and rule-interpretation changes are both reviewable.

## Runtime Rule Sources (authoritative)

Source resolution order is implemented in `RuleLoader.load()`:
1. Application Support main rule file
2. Bundle candidate rule files
3. Built-in fallback rules

Reference:
- `Sources/SpinLabApp/Import/Rules/RuleLoader.swift` lines 34-54, 56-70

Runtime config paths are centralized in:
- `Sources/SpinLabApp/Import/Rules/RulesConfigPaths.swift` lines 27-49

Effective rule file set (maximum 6 files):
- `filename_rules.json` (base)
- `sample_id_rules.json` (override)
- `workflow_match_rules.json` (override)
- `conditions_rules.json` (override)
- `substrate_rules.json` (override)
- `measurement_tag_rules.json` (override)

## Override Merge Semantics

Separated override application is implemented in `applySeparatedOverrides(...)`:
- `sample_id_rules.json`: replaces `sampleId.patterns` when valid and non-empty
- `workflow_match_rules.json`: replaces workflow match rules when valid and non-empty
- `conditions_rules.json`: merges `extraConditions` and key-wise overrides `tokenMapRules` (empty array means explicit clear)
- `substrate_rules.json`: overrides substrate tag rules/shared substrate when provided
- `measurement_tag_rules.json`: replaces measurement tag rules when valid and non-empty

Reference:
- `Sources/SpinLabApp/Import/Rules/RuleLoader.swift` lines 222-437

## Composite Fingerprint Contract

Rule fingerprint is based on:
- primary `filename_rules.json` bytes
- plus every existing separated override file path + bytes

Reference:
- `Sources/SpinLabApp/Import/Rules/RuleLoader.swift` lines 481-499

Metadata exported by loader:
- `version`
- `sourceLabel`
- `sourcePath`
- `contentHash`
- `contentHashPrefix8`
- `loadedOverrideFiles`
- `fingerprint`

Reference:
- `Sources/SpinLabApp/Import/Rules/RuleLoader.swift` lines 11-26, 169-176

## Non-Configurable Interpretation Logic (critical)

The following behavior is hardcoded in parser/evaluator logic and must be treated as rules:

### Default sample key arbitration

Shortcut order:
1. exactly one file sample id -> return directly
2. no file sample id + exactly one folder sample id -> return directly
3. exactly one channel hint -> return directly
4. otherwise scoring path

Scoring weights:
- channel: +100
- file: +60
- folder: +45

Tie behavior:
- same top score -> lexicographic sample id tie-break
- multiple top candidates after tie-break path -> ambiguous warning, default sample key = nil

Low-confidence warning threshold:
- warning is emitted only when `winner.score < SampleKeyScore.file`
- with current weights, this means folder-only winner warns, while file-only/channel winner does not

Reference:
- `Sources/SpinLabApp/Import/Parse/FilenameRuleParser.swift` lines 237-328

### Review-required verdict boundary

Verdict rule:
- `libraryMatched` only when `scopes` is non-empty and all matched
- otherwise `reviewRequired`

Reference:
- `Sources/SpinLabApp/Import/Evaluate/PendingRoutingRuleBook.swift` lines 3-6
- `Sources/SpinLabApp/Import/Evaluate/PendingRoutingSnapshotEvaluator.swift` lines 10-45

## Guardrail Tests (Golden Behavior Map)

Parser arbitration and scoring:
- `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` line 159  
  `parser score arbitration selects unique winner when no single-source shortcut applies`
- `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` line 171  
  `parser leaves default sample empty when top score arbitration ties`
- `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` line 183  
  `channel-only winner is selected without ambiguity warning under channel-first priority`
- `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` line 195  
  `single file sample shortcut wins before score aggregation`
- `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` line 207  
  `single channel sample shortcut wins before single folder sample shortcut`
- `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` line 218  
  `score aggregation lets channel evidence outrank split file and folder evidence`

Verdict boundaries:
- `Tests/SpinLabAppTests/V221RoutingExplanationTests.swift` line 77  
  `rulebook keeps empty scopes as review-required`
- `Tests/SpinLabAppTests/V221RoutingExplanationTests.swift` line 83  
  `snapshot is review-required when any evaluated scope is unmatched`
- `Tests/SpinLabAppTests/V213InboxClosedLoopTests.swift` line 106  
  `file-level queue is library matched when mapped drawer exists`
- `Tests/SpinLabAppTests/V213InboxClosedLoopTests.swift` line 132  
  `channel-level queue requires all reported channels to map drawers`

## Runtime Observability Fields

Runtime state now exposes:
- routing rule source label/path
- routing fingerprint
- routing hash prefix
- loaded override file list

Reference:
- `Sources/SpinLabApp/App/State/InboxFeatureStore.swift` lines 18-22, 346-353
- `Sources/SpinLabApp/App/RegistryFacade.swift` lines 50-59
- `Sources/SpinLabApp/App/SpinLabAppState.swift` lines 1765-1774

## Change Control Checklist (must)

For any change touching rules:
1. If rule files changed: report changed file list and new fingerprint/hash prefix.
2. If parser/evaluator constants or ordering changed: update this manifest and matching golden tests in the same change.
3. If behavior changed intentionally: add/adjust explicit test case with concrete input/output pair.
4. Do not merge rule changes without at least one of:
   - updated golden test, or
   - explicit no-behavior-change proof (same tests pass, same fingerprint reasoning documented).
5. If new separated default rule files are added under `Sources/SpinLabApp/config/`,
   update `scripts/test_rule_drift_guard.sh` guard target list in the same change.

## Local Runtime Snapshot Command (operator)

Use this command to capture current machine runtime rule state:

```bash
ROOT="$HOME/Library/Application Support/SpinLab/config"
ls -la "$ROOT"
for f in filename_rules.json workflow_match_rules.json sample_id_rules.json conditions_rules.json substrate_rules.json measurement_tag_rules.json; do
  p="$ROOT/$f"
  if [ -f "$p" ]; then
    printf "%s\t" "$f"
    shasum -a 256 "$p" | awk '{print $1}'
  fi
done
```
