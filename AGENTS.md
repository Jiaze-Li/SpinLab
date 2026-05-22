# Agent Instructions

> This file contains cross-project engineering methodology and AI strategy.
> Project-specific details live in `specs/` — see Project Reference section at the end.

---

## Instruction Priority (required)

- User explicit instructions are always the highest-priority requirement.
- Do not introduce or apply self-defined rules unless the user explicitly requests them.
- Do not modify docs unless explicitly requested — exception: knowledge accumulation closeout (see below).

---

## Product Scope (required)

- `[HARD][must]` This app is **single-user** — only Jack uses it. Do not introduce code paths, abstractions, or settings for multi-user scenarios, account/permission models, multi-machine sync, or i18n.
- `[HARD][must]` Configuration under `~/Library/Application Support/SpinLab/` is user-specific. Do not propose dotfiles symlinks, cross-machine sync, or git-tracking these files.
- User-specific literals (paths under `/Users/jack/...`, OneDrive container names, fixed prefix lists, registry filenames in Chinese) are acceptable in defaults, fixtures, and docs. Do not refactor them into config templates "for portability" — there are no other users.
- Implication for testing/build: tests must NOT write to real `~/Library/Application Support/SpinLab/` (this is the source of the v5.1.15 root-path-loss incident). Use temp directory injection.

---

## Engineering Quality (required)

- `[HARD][must]` All implementations must follow first-principles reasoning. No redundant, decorative, or non-functional code.
- `[HARD][must]` Prefer long-term maintainability over short-term convenience.
- `[HARD][must]` Sign-off criteria: structural quality + maintainability + testability, not just feature correctness.
- `[HARD][must]` Do not rename, remap, or reformat any user-defined display name, ID, field name, or configuration value unless the user explicitly requests it. "Cleanup" or "normalization" of user-chosen names is forbidden.
- `[HARD][must]` **Desktop app rebuild gate**: a round that includes Swift source changes must end with `./scripts/build_desktop_app.sh debug` to rebuild and overwrite `/Applications/SpinLab.app`. **Skip the rebuild when the round has no `.swift` changes** (docs-only / config-only / handoff-only rounds do not trigger build). A Stop hook (`~/.claude/hooks/spinlab_desktop_build.sh`) enforces this automatically — it compares `Sources/**/*.swift` mtimes against the app bundle and exits silently when nothing is newer, so it is safe to rely on. Execution responsibility still belongs to the AI completing the change when source did move. Full build policy: `docs/architecture/ARCHITECTURE_OVERVIEW.md` §Build and Version Policy.
- `[HARD][must]` After any code change, run `./scripts/check_required_actions.sh` before handoff. Treat its output as the machine-readable action gate for rebuild/publish decisions.
- `[HARD][must]` If `Sources/SpinLabApp/` changed, complete `./scripts/build_desktop_app.sh debug` and update `/Applications/SpinLab.app`.
- `[HARD][must]` If `Resources/WebLibraryTemplate/` or `scripts/export_static_library.py` changed, complete `./scripts/publish_web_library.sh`.
- `[HARD][must]` If both Swift and Web Library inputs changed, do both actions.
- `[HARD][must]` The real app bundle is `/Applications/SpinLab.app`.
- `[HARD][must]` No Desktop `SpinLab.app` bundle, symlink, or alias should exist.
- `[HARD][must]` Final responses must explicitly report whether Swift changed, whether Web UI/export changed, whether rebuild/publish was required, whether each was completed, and the updated app or site result. Do not claim a task is done if a required rebuild or publish was skipped.
- `[HARD][must]` After build/publish-sensitive changes, final responses must include actual command outputs from: `git status --short`, `./scripts/check_required_actions.sh`, `ls -ld /Applications/SpinLab.app`, and `ls -ld ~/Desktop/SpinLab.app || true`.
- `[HARD][must]` 新增 `Sources/**/*.swift` 必须登记到对应 `docs/architecture/<region>/<layer>.md` 的 `## Code Map` 段（4 步 SOP 见下方 `## Adding New Swift Code` 段）。pre-commit hook 强制检查；准备 commit 含 `Sources/**/*.swift` 增删/重命名前，确认 `.git/hooks/pre-commit` 含 `spinlab-architecture-coverage:start` sentinel——首次提交前跑 `scripts/install_git_hooks.sh --check || scripts/install_git_hooks.sh` 自举安装。
- Execution gate and collaboration model: inherited from global `~/.claude/CLAUDE.md`.

---

## Adding New Swift Code (required)

新增 `Sources/**/*.swift` 必须走以下 4 步登记到对应区/层 `## Code Map` 段；pre-commit hook 兜底。

### 步骤

1. **写代码**。
2. **决定 region / layer**（判定树见下）。
3. **在 `docs/architecture/<region>/<layer>.md` 的 `## Code Map` 段加一行**：

   `` - `Sources/...swift` — <一句主动短句描述稳定职责> ``

   **注释体例**（`[HARD]`）：
   - 主动短句，描述稳定职责（"coordinates X across Y"，不是"called by Z to handle..."）
   - 不写条件从句（"when ... then ..."）
   - 不写临时实现原因（"workaround for...""until..."）
   - 不写测试结论（"verified passing in V515..."）
   - 不写调用方信息（"used by ApplyCoordinator"）
   - 长度建议 ≤ 80 字符（不强制）

4. **`git commit`**（已安装 pre-commit hook 时自动走 `verify_architecture_code_coverage.sh --check-only`）。

### 第 2 步判定树

**先 region**（按消费者/行为，不按物理目录）：

- Input/parse/route/match/evaluate/RulesPanel UI/Rule schema → **inbox**
  - 子层：ROUTING_PIPELINE.md（parse/match）/ RULES_AUTHORING.md（rule schema/RulesPanel）/ CONFIRM_AND_APPLY.md（pending review/apply-to-library）/ OUTPUT_CONTRACTS.md（registry, sidecar 输出契约）
- Library 浏览/编辑/持久化/registry 同步/sidecar 查看 → **library**
  - 子层：BROWSE_AND_SELECTION.md / SAMPLE_METADATA_EDITING.md / ARCHIVE_STORAGE.md / SIDECAR_AND_CONDITIONS.md / ARTIFACTS_AND_PREVIEWS.md
- Measurement search/workflow analysis/plot shell/chart 持久化 → **workbench**
  - 子层：SHELL_AND_LIFECYCLE.md / MEASUREMENT_SEARCH.md / PLOT_CANVAS.md / WORKFLOW_CONTRACTS.md / ARTIFACT_PERSISTENCE.md / EXTENSION_BOUNDARIES.md
- App shell / global DI/navigation/logging / Domain contracts / Registry bridge / 共享 UI/storage → **按主 owner（消费频率最高的 region）** 登记到既有 region/layer 的 `## Code Map`；*不*在 `architecture/INDEX.md` 重复登记。

**跨两 region 时**：canonical Code Map 只在主 owner 一处；collaborator region 默认不重复登记同一文件。

**判定树兜底**：拿不准 → pre-commit hook 报 unmapped 后看候选区/层提示，3 选 1。

### 维护

- 修改既有 swift 文件核心职责后，反查 `## Code Map` 注释是否仍准确；偏离则补改（触发点：Session Closeout 第 6 条）。
- rename / 删除：双向集合差天然覆盖；改了就 commit，hook 报什么改什么。

---

## Rule Labels (required)

- `[HARD]`: non-negotiable constraint; violating = bug risk.
- `[DIRECTION]`: preferred direction; violating allowed only with explicit short-term rationale.
- `[GOAL]`: target architecture; may be partially unmet during migration.
- `must`: required in this change unless user explicitly overrides.
- `should`: preferred; may be deferred when scope/time is constrained.

---

## Architecture Patterns (required)

### Feature Store

- `[HARD][must]` New feature state must be introduced through a FeatureStore, not raw root properties on AppState.
- `[HARD][must]` Interactive observable stores: `@MainActor @Observable final class`.
- `[HARD][must]` AppState exposes stores via namespace properties and coordinates across them.
- `[DIRECTION][should]` FeatureStore owns its repository references and projection stream wiring.
- `[DIRECTION][should]` Complex mutating operations expose explicit outcomes (enum/result).
- `[GOAL][should]` AppState remains an app shell: cross-store coordination + global concerns only.
- Exception: small presentation-only state containers may be `struct`.
- Exception: FeatureStore may hold **side-effect-free** services via `@ObservationIgnored` + init substitute parameter (DI Tier 2). Side-effect repositories/storage/loggers must be received via AppEnvironment (DI Tier 3) — not held as default-constructed properties.

### Architecture Decision Boundary

- Logic touches one feature domain → FeatureStore.
- Logic coordinates 2+ stores (or store + navigation/alert/audit) → AppState.
- Deterministic, side-effect-free → UseCase.
- Long-lived state or multi-step orchestration → Service/Orchestrator.

---

## Platform and Technology (required)

- Minimum target: macOS 14.
- State management: Swift 5.9+ `@Observable` macro exclusively.
  - Do NOT use ObservableObject, @Published, @StateObject, @EnvironmentObject.
  - Do NOT introduce Combine pipelines for state; use AsyncStream or async/await.
- Concurrency: Swift Structured Concurrency (async/await, actors, AsyncStream).
  - Do NOT use DispatchQueue, NotificationCenter, or completion-handler APIs in new code.
- No third-party dependencies without explicit user approval.

---

## State Management (required)

- `@Observable final class` for observable state objects.
- `@ObservationIgnored` for internal caches, lazy services, Task handles.
- `private(set) var` for view-readable, non-writable properties.
- AppState methods must remain synchronous. Delegate async work to a data actor.
- ViewModel owns transient UI state only (expansion, filter text, local selection).
  - ViewModel must not own canonical domain models.
  - Sync with AppState via explicit `restoreInteractionState()` / `persistInteractionState()` only.
  - No property observers or reactive pipelines for auto-sync.

---

## Error Handling (required)

- UseCases may return `Result<Output, AppError>` or throw `AppError`. Both acceptable.
- All errors must be mapped to `AppError` before reaching AppState.
- Never use `try?` to silently discard errors in service/repository/storage layers.
  - `try?` acceptable only for non-critical UI convenience reads.
- AppState surfaces errors to the UI.

---

## Concurrency (required)

- Repositories: `AsyncStream<T>` + Continuation. Never Combine.
- Heavy I/O: run inside data actor, not inside `@Observable` classes.
- `@Observable` class methods must not be async. Spawn internal Tasks if needed.

---

## Dependency Injection (required)

### DI Three-Level Classification

| Dependency Type | Substitution Mechanism |
|---|---|
| Pure value helper / pure function | instantiate directly |
| Side-effect-free service | init default parameter + `@ObservationIgnored` + init substitute parameter |
| Side-effect dep (repository / logger / storage / filesystem / network / `.shared` singleton) | **must go through AppEnvironment / capability protocol** |

- All runtime dependencies with side effects declared in AppEnvironment.
- Prefer capability protocols over concrete types.
- UseCases: stateless structs, receive dependencies as function parameters.
- AppState stores AppEnvironment fields as `@ObservationIgnored private` properties.
- `[HARD][must]` Side-effect dependencies must NOT use default construction inside FeatureStore or UseCase (no bare `Store()` / `Service()` instantiation at declaration site).

---

## Layered Architecture (required)

- Pipeline: Input → Parser → Model → UseCase/Service → Repository/Store → UI.
- Parser: parse source structure, preserve source order.
- Model: carry raw data + ordered projections.
- UseCase/Service: execute workflows, no SwiftUI import, no storage details.
- Repository/Store: persistence only, no business policy.
- UI: render only, no sort/infer/filter/rewrite of business semantics.

---

## Legacy Cleanup (required)

- `[HARD][must]` When replacing old behavior, remove superseded code paths in the same change.
- `[HARD][must]` Cleanup includes runtime artifacts (config files, cached state), not just source.
- `[HARD][must]` After cleanup, verify runtime-loaded and bundled rules are aligned.
- `[DIRECTION][should]` Backward compatibility in config aliases only, not duplicated Swift logic.

---

## Domain Models (required)

- All domain models: `struct`, conforming to `Codable`, `Hashable`, `Sendable`. Add `Identifiable` where applicable.
- Use `enum` for closed-set values. Never String constants.
- Raw models carry source data only. UI projections are separate presentation structs.

### Domain Three-Tier Placement

| Tier | Definition | Physical Location | Content Boundary |
|---|---|---|---|
| Tier 1 cross-region contract | consumed by ≥ 2 regions | `Sources/Domain/<topic>/` | `Codable/Hashable/Sendable` contract **only**; no parser/loader/evaluator/repository/service I/O |
| Tier 2 region domain entity | single-region persistence + UseCase shared | `Sources/<Region>/Domain/` | same pure-value constraint |
| Tier 3 UI projection | View + ViewModel only | `Sources/<Region>/Features/` | must NOT be imported by UseCase layer |

**Migration criteria (write criteria, not pre-committed file paths):**
- "Is this type a pure `Codable/Hashable/Sendable` value contract?" → yes: migrate to Tier 1 or 2; no: leave in owner region.
- "Does this file mix contract + behavior (loader/evaluator/parser)?" → yes: split first, migrate only the contract portion.
- `legitimate_cross_cutting` marker: after physical migration to `Domain/`, preserve as collaborator-region Code Map comment identifying cross-region consumer identity. Do not remove this marker.

`[HARD][must]` When migrating a file to Tier 1 `Sources/Domain/`, enforce `Codable/Hashable/Sendable` conformance. Moving the file without adding required conformances is an incomplete commit.

---

## View Layer (required)

- Views receive AppState via `@Environment`. Never pass as init parameter.
- Views own ViewModel via `@State`. Pass to children via `@Bindable`.
- Views must not call service/repository/parser/storage directly — go through AppState or ViewModel.
- Views must not contain sorting/filtering/normalization logic.
- Services and UseCases must have no SwiftUI import.
- `[HARD][must]` UI visual rules (fonts, spacing, buttons, accessibility): see `specs/04_UI_RULES.md`.

---

## Separation Rules (required)

- UI must not decide metadata ordering rules.
- When a change touches both UI and logic/storage, split into separate tasks and commits.
- UI must not call services/repositories directly.
- Parser must not call Service/Repository. Service may call Repository.
- Side effects must not occur inside `@Observable` state setters.

---

## New Feature Sequencing (required)

Implement only the layers that require change, in this order:
1. Domain model change — if domain types affected
2. Repository/persistence — if new data needs storage
3. UseCase/Service logic — if business workflow changes
4. UI last — always last

Do not implement out of order. Skip steps when that layer has no change.

---

## Naming Convention (required)

- Files: `FeatureView.swift`, `FeatureViewModel.swift`, `ActionNameUseCase.swift`, `ServiceNameService.swift`, `NameStore.swift`.
- Test files: `V{major}{minor}{patch}FeatureNameTests.swift`.
- `@Observable` classes: `final class`, PascalCase.
- Capability protocols: suffix with `Capability` or `Providing`.
- Do not suffix domain enums with `Type`/`Kind` unless already established.

---

## Testing (required)

- New features at version vX.Y.Z must have corresponding `VXYZFeatureNameTests.swift`.
- Parser/matching tests: concrete input/expected-output pairs, not mocks.
- UseCase tests: real or fixture repositories, not mocks.
- Test files live in `Tests/`. Do not place near source files.

---

## UI-only Change Isolation (required)

- UI-only requests must not change parser/state/registry/service/store logic.
- UI-only requests must not alter behavior of unrelated partitions.
- Scope UI edits to the explicitly requested partition/component only.
- UI should minimize repeated or low-value information.

---

## Knowledge Accumulation (required)

### Session Startup
- `[HARD][must]` Read `docs/philosophy.md` and `docs/features.md` on entering the project.
- `[HARD][must]` Run `ls tmp/` and triage residue per `~/.claude/docs/workflow.md §9.d` tmp lifecycle rules（留 / 升级到 docs/handoff / 删；超 14 天默认提示 Jack）.
- `[DIRECTION][should]` Read relevant `docs/history/` entries for architecture tasks.

### Handoff Pointer Registry (overrides global workflow.md §9.a)
- `[HARD][must]` SpinLab 的 handoff 指针登记落点是 **`docs/TASK_BOARD.md`** 的「进行中」表（不是全局规则里的 `docs/ledger/l1_优化待办.md`，本项目无 ledger 体系）。
- 产出 handoff 时：(1) `mv` 草稿到 `docs/handoff/<YYYY-MM-DD-topic>.md`，(2) 在 TASK_BOARD「进行中」表对应行翻状态为「方案完成 (s<n>)」+ 指针列改指 handoff 文件。归档时（§9.c）整行删 + history/INDEX 加一行。

### Session Closeout (event-driven)
- `[HARD][must]` After code changes, walk through:
  1. User-visible behavior changed? → Update `docs/features.md`.
  2. New development preference? → Update `docs/philosophy.md`.
  3. Cross-session user preference? → Write to memory system.
  4. 接手并完成了某份 handoff？→ 按 `~/.claude/docs/workflow.md §9.c` 4 步归档动作执行（handoff 搬迁 + 索引更新 + 设计思路 ROADMAP→history 迁移 + ROADMAP 改一句话+`[x]`）。
  5. 是否动了流水线状态（出 handoff / 第一次 commit / 归档完成）？→ 同步翻 `docs/TASK_BOARD.md` 状态或删行；归档时同步在 `docs/history/INDEX.md` 加一行。详见 `docs/TASK_BOARD.md` 末尾「维护规则」段。
  6. 改动 `Sources/` swift 文件 → 反查对应 `## Code Map` 条目注释是否仍准确（职责描述是否偏离当前实现）；偏离则补改注释行。
- Skip steps that don't apply.
- `[HARD][must]` **任务流水线文档职责不可越界**：每份文档只装一种内容。详见 `docs/README.md` 顶部「任务流水线文档职责」表 + 反模式段。设计思路一辈子只活一处（ROADMAP 在做时 / history 做完后），不重复、不互灌。

### Change Impact
- `[HARD][must]` Before modifying code, check `docs/features.md` invariants. If a change would violate one, flag it before proceeding.

---

## Roadmap Reference

- Active roadmap: `docs/V5_ROADMAP.md`. ROADMAP 三态、互相引用方向、反模式 → 见 `~/.claude/docs/workflow.md §3.e`。
- Discovered bugs/debt: 先进 `docs/TASK_BOARD.md`「待拍板」段；Jack 拍板归入版本段时迁入「进行中」段（状态 =「需求提出」），同步从「待拍板」删（避免双账本）。
- Do not reorder/reprioritize unless user instructs.
- 一次规划只针对**一条需求**，不批量处理 ROADMAP 多条。

---

## Project Reference (SpinLab-specific)

Project-specific architecture, code placement, module contracts, and checklists are in:
- `docs/architecture/ARCHITECTURE_OVERVIEW.md` — code placement, canonical implementations, Import pipeline, AppState/FeatureStore boundaries, UI shell patterns
- `docs/architecture/workbench/INDEX.md` — Workbench subsystem: shell lifecycle, search, plot canvas, workflow contracts, artifact persistence, extension boundaries
- `specs/04_UI_RULES.md` — visual rules (fonts, spacing, buttons, disclosure sections, accessibility)
- `specs/01_PRODUCT_RULES.md` — product behavior contract
- `specs/02_DATA_RULES.md` — domain model and data rules
- `docs/architecture/inbox/` — Inbox subsystem: routing pipeline, rules authoring, confirm/apply, output contracts
- `docs/architecture/workbench/` — Workbench subsystem: shell lifecycle, search, plot canvas, workflow contracts, artifact persistence, 3ω physics (`architecture/workbench/THREE_OMEGA_PHYSICS.md`), extension boundaries

Read the relevant spec when the task touches that area. Do not read all specs every session. Long-term product/architecture philosophy lives in `docs/philosophy.md`, not in specs.
