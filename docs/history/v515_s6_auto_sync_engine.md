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
