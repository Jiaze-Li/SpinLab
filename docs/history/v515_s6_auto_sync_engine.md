# v5.1.5 s6 — Rules Auto-Sync Engine: Implementation Summary

**Completed**: 2026-04-26  
**Commits**: 99514e2 (s6a) + 4a586fe (s6b)  
**Tests**: 68/68 V515 suite green (20 engine + 12 startup + 36 pre-existing panel tests)

---

## What was built

### RepositoryPointer (`Storage/RepositoryPointer.swift`)
Parses and validates `.repo_pointer.json`. Version==1 only; requires non-empty `repository_config_dir` and `repo_root`; canonicalizes via `standardizedFileURL.resolvingSymlinksInPath()`; identity-checks that `repo_root` is an existing directory containing `.git` and that `repository_config_dir` is under `repo_root`. Returns nil on any failure (mirror silently skipped).

Auto-write on first cold dev start: walks up 12 levels from `Bundle.main.bundleURL` looking for `Sources/SpinLabApp/config` + `.git`; writes pointer then re-reads it. Guarded by `RulesConfigPaths.isRunningTests()` — no auto-write in test environments.

### RulesSyncEngine (`Storage/RulesSyncEngine.swift`)
`dualWrite(runtimeURL:data:sectionLabel:)` — writes runtime first (throws on failure), then resolves mirror dir and writes mirror (non-throwing; returns `.mirrorFailedRuntimeOk` on failure). Backs up both sides before overwriting.

`reverseSyncOnStartup(runtimePaths:)` — iterates all 5 rule files; for each: reads mirror, decode-checks (H5 guard using `SchemaKind.canDecode()`), SHA-256 hash-compares; if different: backs up runtime file, writes mirror content. Returns `.healthy` / `.skipped` / `.degraded(failedFiles:reason:)`.

Mirror resolution: `testOverrideMirrorURL` if set (bypasses test guard), else nil if `isRunningTests()`, else `pointer?.repositoryConfigDir`.

### RulesManagementStore additions
- `syncStartupOutcome: StartupOutcome` — injected from AppState init
- `mirrorWarningSectionLabel: String?` + `mirrorWarningReason: String?` — set/cleared on each save
- `persist()` delegates to `syncEngine.dualWrite()` when engine present; falls back to direct `atomicWriter.write()`
- `savedWithMirrorWarning(reason:)` added to `RulesPanelSaveOutcome`
- `persistenceHook.didPersist` gains 5th parameter: `DualWriteOutcome`

### SpinLabAppState startup sequence
In `init()`, before `load()`: resolves `RepositoryPointer.load(runtimeConfigDir:)`, constructs `RulesSyncEngine`, calls `reverseSyncOnStartup`, then `RuleLoader.shared.reloadCached()`. Injects engine + outcome into `rulesPanelStore`.

### RulesPanelView UI
- Degraded banner: orange background, warning icon, caption text, dismiss button (`.help` shows full reason). Shown at top of sidebar when `syncStartupOutcome == .degraded` and not yet dismissed.
- Mirror warning icon: `exclamationmark.triangle.fill` in sidebar row when `mirrorWarningSectionLabel` matches section.

---

## Key design decisions

**H5 decode guard**: mirror file must successfully decode as the appropriate Draft type before being accepted as authority. Prevents corrupt or mismatched-schema mirror from overwriting a valid runtime file.

**Runtime-first write**: if runtime write fails, `dualWrite` throws and mirror is never touched. Mirror failure is always non-fatal.

**Hash comparison (not mtime)**: git does not preserve mtime; content hash is the only reliable signal.

**M7 rejected**: Codex proposed `.backup` files use timestamp suffixes. Rejected — single `.json.backup` is simpler, sufficient, and prevents backup accumulation. Each write overwrites the previous backup.

**Test isolation**: startup tests use real `RulesConfigPaths` PID-isolated dirs + temp fake git repos as mirror targets. No mock filesystem needed.

---

## §7 实机 verification (2026-04-26 21:22)

Performed via repackaged `/tmp/SpinLab-s6.app` (copy of `/Users/jack/Desktop/SpinLab.app` Info.plist + Contents shell, MacOS binary swapped to fresh `swift build` of s6) running against real `~/Library/Application Support/SpinLab/config/`. Pre-s6 production app at PID 61971 was quit by user before the run. Runtime config directory was backed up to `~/Downloads/spinlab-s6-acceptance-backup-20260426-211056/` and restored bit-identical after each scenario.

| # | Scenario | Method | Result |
|---|---|---|---|
| 1 | Cold start (real path) | `rm -rf SpinLab/config` + pre-write valid pointer + `open .app` | ✓ pointer survives + log `sync engine: reverse sync updated workflow.json from repository mirror` + 5 runtime files hash-match bundle mirror. (Other 4 files seeded by RulesMigration before reverseSync ran, so they hit the "consistent, skip" branch — by design; sync engine confirms consistency rather than duplicates migration.) |
| 3 | Pull-then-restart | Edit mirror `workflow.json` (added marker key) + restart | ✓ log `reverse sync updated workflow.json` + runtime hash now == new mirror hash + `workflow.json.backup` contains pre-sync runtime content. |
| 6 | Cross-repo pollution | Pointer `repo_root: /tmp/spinlab-s6-fake-repo` (no `.git`) + restart | ✓ warning `repo pointer identity check failed: repo_root does not contain .git, skipping mirror` + `sync engine: no repo pointer, skipping reverse sync` (engine rejects pointer) + runtime workflow.json byte-unchanged. |
| 7 | Mirror schema corruption | Replace mirror `workflow.json` with `{ "broken": json invalid` + run dev binary | ✓ `errorTaxonomy: decode_failed` + `sync engine: startup degraded after reverse sync` with `failedFiles: workflow.json`. (Run via dev `swift build` binary in per-PID sandbox; same code path as `.app`.) |
| 2 | Save dual-write | Open Rules panel → Import Filters → Add `s6test` extension → Save | ✓ git status mirror modified + runtime/mirror sha-256 match (`4cfee42d…`) + both sides have `.json.backup`. Driven via real GUI clicks. |
| 4 | Save with absent pointer | `rm .repo_pointer.json` → restart → Add `s6test4` → Save | ✓ runtime contains `s6test4` + mirror clean (no git diff) + mirror does not contain `s6test4`. Save outcome `.saved` (no warning indicator on sidebar). |
| 5 | Save with mirror unwritable | `chmod -w mirror` + restart → Add `s6test5` → Save | ✓ log error `sync engine: mirror write failed for importFilters` with reason `permission denied` + runtime contains `s6test5` + mirror unchanged + sidebar shows orange warning icon (`exclamationmark.triangle.fill`) next to Import Filters only. |

**Cold-start path detection (incidental finding)**: dev binary auto-writes pointer correctly via `Bundle.main.bundleURL` walk-up (verified in PID-sandbox at `~/Library/Application Support/com.spinlab.tests.<PID>/config/`). Packaged `.app` at `/tmp/SpinLab-s6.app` correctly does NOT auto-write (heuristic fails to find `Sources/SpinLabApp/config` + `.git` siblings of `.app` bundle), logging `repo pointer: absent and no dev repo detected, skipping mirror`. This is the designed end-user behavior — distributed binaries don't have source repo, mirror sync is correctly off.

**Logs**: aggregated under `~/Library/Application Support/SpinLab/logs/app_events.log` (s6 acceptance run, lines 3431–3590). No unexpected error / warning entries outside the deliberately induced ones in scenarios 5, 6, 7.

**Cleanup**: `/tmp/SpinLab-s6.app` removed; mirror reverted via `git checkout`; runtime restored bit-identical from backup `~/Downloads/spinlab-s6-acceptance-backup-20260426-211056/`; `git status` clean (only this history file modified).
