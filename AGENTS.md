# SpinLab Agent Instructions

SpinLab is a macOS research app for magnetic experiment workflow management.

Core structure:
Inbox
Workbench
Library

Core workflow:
Import → Confirm → Visualize → Analyze → Save → Archive

Core objects:
Project
Batch
Sample
Device
Measurement
Dataset
Result
Comparison

Rules:
Sample can belong to multiple projects.
Batch is different from physical sample.
Device is optional.
Dataset maps to one measurement by default.
Results can be rated.

Workflow ID mapping (v4.1.3+):
| Old ID | New ID | Workflow |
|--------|--------|----------|
| A      | ahe    | AMR/PHE (Anomalous Hall Effect) |
| B      | 3w     | 3 Omega |

If you encounter `"A"` or `"B"` as workflowID in sidecar files, persisted JSON, or logs, it is a pre-v4.1.3 artifact. Replace with the new ID. No backward-compatibility code exists.

---

Instruction priority policy (required):
- User explicit instructions are always the highest-priority requirement for implementation behavior.
- Do not introduce or apply self-defined rules unless the user explicitly requests them.
- Do not modify docs (including UI/design rules) unless the user explicitly requests doc updates — exception: Knowledge accumulation closeout rule (see below) permits updating `docs/features.md`, `docs/philosophy.md`, `docs/known_issues.md`, `docs/history/`, and `docs/README.md` as part of the session closeout judgment tree after substantive code changes.

---

Engineering quality (required):
- `[HARD][must]` All implementations must follow first-principles reasoning. Do not add redundant, decorative, or non-functional code.
- `[HARD][must]` Prefer long-term maintainability over short-term convenience. Reject approaches that are fast now but increase future complexity/cost.
- `[HARD][must]` Sign-off criteria are structural quality + maintainability + testability, not just feature-level correctness.
- Execution gate and collaboration model: inherited from global `~/.claude/CLAUDE.md`.
- `[HARD][must]` Do not rename, remap, or reformat any user-defined display name, workflow ID, condition field name, or configuration value unless the user explicitly requests that specific rename. "Cleanup" or "normalization" of user-chosen names is forbidden. 迁移或兼容性转换（如旧 ID 到新 ID）也必须获得用户明确指令后才可执行。

---

Rule stability and enforcement (required):
- Rule labels:
  - `[HARD]`: non-negotiable constraint; violating this is considered a bug risk.
  - `[DIRECTION]`: preferred direction; violating this is allowed only with explicit short-term rationale.
  - `[GOAL]`: target architecture; may be partially unmet during migration.
- Enforcement terms:
  - `must`: required in this change unless user explicitly overrides.
  - `should`: preferred; may be deferred when scope/time is constrained.

---

Where does new code go? (required):

| Code shape | Destination |
|---|---|
| New observable feature state | FeatureStore in `Sources/SpinLabApp/App/State/` |
| Cross-feature coordination | `SpinLabAppState` methods |
| Complex operation within a single feature | FeatureStore method returning `Outcome` enum/result |
| Stateless business operation (Input -> Output) | `Sources/SpinLabApp/UseCases/` struct |
| Stateful domain service/orchestration | Service/Orchestrator in `Sources/SpinLabApp/App/` or domain module |
| External I/O (filesystem/persistence) | Repository/Store layer |
| Filename parsing/matching/routing rules | `Sources/SpinLabApp/Import/` pipeline layers |
| Pure UI interaction state (expand/collapse/filter text) | `FeatureViewModel` |

Architecture decision boundary (required):
- If logic touches exactly one feature state domain, it `must` go to that FeatureStore.
- If logic coordinates two or more stores (or store + navigation/alert/audit), it `must` stay in `SpinLabAppState`.
- If logic is deterministic and side-effect-free with explicit input/output, it `should` be a UseCase.
- If logic has long-lived state or multi-step workflow orchestration, it `should` be a Service/Orchestrator.

---

Feature Store pattern (required):
- `[HARD][must]` New feature state must be introduced through a FeatureStore namespace, not as raw root properties on `SpinLabAppState`.
- `[HARD][must]` For interactive observable stores, use `@MainActor @Observable final class`.
- `[DIRECTION][should]` FeatureStore owns its domain repository references and projection stream wiring.
- `[DIRECTION][should]` Complex mutating operations expose explicit outcomes (enum/result), not implicit side effects only.
- `[HARD][must]` AppState exposes stores via namespace properties (`inbox`, `library`, `workbench`, etc.) and coordinates across them.
- `[GOAL][should]` `SpinLabAppState` remains an app shell focused on:
  1. cross-store coordination
  2. global concerns (navigation, alert, audit)

FeatureStore exception:
- `[HARD][must]` Small presentation-only state containers with no autonomous behavior may be `struct` instead of `@Observable final class` (example: `RegistryFeatureStore`).

---

Canonical implementations (reference):
- Feature Store pattern:
  - `Sources/SpinLabApp/App/State/InboxFeatureStore.swift`
  - `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift`
- UseCase (sync flow):
  - `Sources/SpinLabApp/UseCases/ConfirmPendingImportUseCase.swift`
- UseCase (non-fatal error channel):
  - `Sources/SpinLabApp/UseCases/SaveLibrarySampleEditsUseCase.swift`
- Repository + AsyncStream projection:
  - `Sources/SpinLabApp/Repositories/DomainRepositories.swift`
- Routing pipeline boundary example:
  - `Sources/SpinLabApp/Import/Evaluate/PendingRoutingSnapshotEvaluator.swift`
- Projection drain and projection subscription handling:
  - `Sources/SpinLabApp/App/State/InboxFeatureStore.swift`
- Integration test scaffold:
  - `Tests/SpinLabAppTests/V223AppEnvironmentIntegrationTests.swift`

---

Pre-merge architecture checklist (required):
- No new root passthrough property was added to `SpinLabAppState` for single-domain state.
- Single-domain logic added in this change lives in its FeatureStore.
- Cross-domain logic added in this change lives in `SpinLabAppState`.
- New/changed behavior has tests in `Tests/SpinLabAppTests/` at matching version prefix.
- `./scripts/build_desktop_app.sh debug` was executed and succeeded after all source changes.

Anti-patterns (forbidden):
- Adding new `library*` / `inbox*` / `workbench*` state fields directly on `SpinLabAppState` when a FeatureStore already exists.
- Calling Repository/Store directly from Views.
- Mixing UI-only changes with parser/state/storage logic in one undifferentiated commit.

---

Temporary exceptions during migration (required):
- Purpose:
  - Prevent agents from treating in-progress refactor seams as permanent architecture violations.
- Handling rules:
  - `[HARD][must]` Do not expand any temporary exception scope.
  - `[HARD][must]` Any change touching a temporary exception must either reduce it or keep it flat with explicit rationale.
  - `[DIRECTION][should]` Prefer deleting compatibility surfaces over adding new ones.

Current temporary exceptions (as of v2.2.1):
- `SpinLabAppState` still contains part of Library-domain behavior during ongoing AppShell migration.
  - Constraint: new single-domain Library logic should go to `LibraryFeatureStore`, not AppState.
- Some root-level compatibility properties remain for interaction snapshot and route continuity.
  - Constraint: do not add new root passthroughs; migrate call sites to namespaced store access first, then remove compatibility properties.

Exit criteria:
- `SpinLabAppState` only keeps:
  - selected area
  - global alert/audit/navigation concerns
  - cross-store orchestration
  - store references
- Single-domain feature behavior is fully owned by corresponding FeatureStore.

---

Platform and technology policy (required):
- Minimum target: macOS 14. Do not use APIs unavailable below macOS 14.
- State management: use Swift 5.9+ @Observable macro exclusively.
  - Do NOT use ObservableObject, @Published, @StateObject, or @EnvironmentObject.
  - Do NOT introduce Combine pipelines for state; use AsyncStream or async/await instead.
- Concurrency: use Swift Structured Concurrency (async/await, actors, AsyncStream).
  - Do NOT use DispatchQueue, NotificationCenter, or completion-handler-based APIs in new code.
- No third-party dependencies may be added without explicit user approval.

---

State management policy (required):
- Use `@Observable final class` for observable state objects.
  - Exception: presentation-only containers with no autonomous behavior may be plain `struct` (see Feature Store exception).
- Use @ObservationIgnored for internal caches, lazy services, and Task handles that must not trigger view re-renders.
  - All lazy services stored inside AppState must be @ObservationIgnored.
- Use private(set) var for properties that views should read but not write directly.
- AppState methods must remain synchronous. Long-running async work must be delegated to SpinLabDataActor.
  - AppState may spawn internal Tasks to call actor methods but must not expose async functions to views.
- ViewModel owns transient UI state only (expansion state, filter text, local selection).
  - ViewModel must not own canonical domain models; those belong to AppState.
  - ViewModel syncs with AppState via explicit restoreInteractionState() and persistInteractionState() methods only.
  - Do not use property observers or reactive pipelines to auto-sync ViewModel with AppState.

---

Error handling policy (required):
- UseCases may return Result<Output, AppError> or throw AppError. Both are acceptable.
  - Prefer Result<Output, AppError> for synchronous UseCases (consistent with existing codebase).
  - Prefer async throws for async UseCases where Result adds unnecessary wrapping.
- Regardless of style, all errors must be mapped to AppError before reaching AppState.
  - Use AppError.from(_ error: Error, fallback: String) for unmapped errors.
  - Use typed cases: .validation, .notFound, .io, .sync, .state for known failure categories.
- Never use try? to silently discard errors in service, repository, or storage layers.
  - try? is acceptable only for non-critical UI convenience reads (e.g., loading optional preview data).
- Propagate AppError up to AppState; AppState is responsible for surfacing errors to the UI.

---

Concurrency policy (required):
- Repositories must use AsyncStream<T> + Continuation for data flow. Never use Combine publishers.
  - Yield the continuation in init; call finish() in deinit.
- Heavy I/O (XLSX parsing, filesystem scanning, registry sync) must run inside SpinLabDataActor.
  - Do not perform file I/O directly inside @Observable classes.
- Do not make @Observable class methods async. Spawn internal Tasks if needed, keep the method signature synchronous.

---

Dependency injection policy (required):
- All runtime dependencies with side effects (persistence, storage, sync, network) must be declared in AppEnvironment and provided via AppEnvironment.live().
- Prefer capability protocols over concrete types in AppEnvironment fields.
  - Example: var planner: any RoutePlanningCapability, not var planner: SpinLabRoutePlanner.
- UseCases must receive repositories and factories as function call parameters, not as stored properties or captured globals.
  - UseCases must be stateless structs or enums with no @Observable annotation.
- AppState stores AppEnvironment fields as @ObservationIgnored private properties.
- Exception: read-only, side-effect-free singletons (e.g., RuleLoader.shared) do not need to go through AppEnvironment. They may be called directly from parsers and services.

---

Layered architecture policy (global, not Library-only):
- Enforce pipeline: Input (files/Excel) → Parser → Model → UseCase/Service → Repository/Store → UI.
- Parser responsibility: parse source structure and preserve source order semantics (e.g., XLSX column order).
- Model responsibility: carry both raw data and ordered/view-ready projections when order matters.
- UseCase/Service responsibility: execute workflows (refresh/diff/confirm/import) with no SwiftUI import and no storage details.
- Repository/Store responsibility: persistence and filesystem operations only; no business policy decisions.
- UI responsibility: render model/view-model data only; do not sort, infer, filter, or rewrite business semantics.

---

Import pipeline policy (required):
- Strictly enforce the five-stage boundary: Parse → Route → Match → Evaluate → Presentation.
  - Parse/: filename tokenization only. No routing decisions.
  - Route/: generate RoutePlan candidates only. No final verdict.
  - Match/: library drawer matching only. No UI projection.
  - Evaluate/: compute final RouteStatus verdict only. No direct UI output.
  - Presentation/: convert routing data to UI structs only. No business logic.
- InboxRoutingState is the only façade connecting the routing pipeline to AppState. Do not bypass it.
- Filename matching rules must live in filename_rules.json and be loaded via RuleLoader.shared. Do not hard-code patterns in Swift source.

---

Legacy cleanup policy (required):
- `[HARD][must]` When a change replaces old behavior (rules, parsing, matching, display mapping), remove superseded code paths in the same change. Do not leave dead fallback branches.
- `[HARD][must]` Cleanup scope includes runtime artifacts, not only source code:
  - App runtime override config (e.g. `~/Library/Application Support/com.spinlab.app/config/filename_rules.json`)
  - Cached or persisted state whose semantics are changed by the update
- `[HARD][must]` After cleanup, verify that runtime-loaded rules and bundled rules are aligned (hash/path/source check) before sign-off.
- `[DIRECTION][should]` If backward compatibility is needed, keep compatibility only in configuration aliases, not in duplicated Swift hard-coded logic.

---

Domain model policy (required):
- All domain models must be struct, not class.
- All domain models must explicitly conform to Codable, Hashable, and Sendable. Add Identifiable where applicable.
- Domain models live in Domain/ or Library/LibraryModels.swift. Do not define domain types inside Features/.
- Use enum for closed-set values (WorkflowKind, RouteStatus, MeasurementType). Never use String constants for these.
- Raw domain models carry source data only. UI-ready projections are separate presentation structs in Import/Presentation/.

---

Extension module policy (required):
- New workflow support must be implemented through all four extension protocols:
  WorkflowExtension, MetadataExtension, AnalysisModuleExtension, ViewExtension.
- Extension implementations must be registered in WorkflowRegistry.registerBuiltins().
- Extension modules must NOT import Features/ or App/ modules.
  - They may only depend on Domain types and protocol contracts in Extensions/ExtensionPoints.swift.
- New measurement types must be added to the domain enum first, then implemented in the relevant workflow extension.

---

View layer policy (required):
- Views receive AppState via @Environment(SpinLabAppState.self). Never pass AppState as an init parameter.
- Views own their ViewModel via @State private var viewModel = FeatureViewModel().
- Pass an @Observable ViewModel into child views for two-way binding using @Bindable.
- Views must not call service, repository, parser, or storage methods directly.
  - All actions must go through AppState methods or ViewModel methods that delegate to AppState.
- Views must not contain sorting, filtering, or normalization logic.
  - UI-only ordering belongs in ViewModel. Domain-affecting logic belongs in UseCase/Service.
- Services and UseCases must have no SwiftUI import.

---

UI-only change isolation checklist (required):
- UI-only requests must not change parser/state/registry/service/store logic.
- UI-only requests must not alter behavior of unrelated functional partitions.
- Scope UI edits to the explicitly requested partition/component only.
- UI should minimize repeated or low-value information; avoid presenting the same facts in multiple panels unless each instance serves a distinct workflow purpose.

---

Change boundary policy (strict):
UI-only tasks may modify only the feature directory corresponding to the requested change:
- Sources/SpinLabApp/Features/Inbox/** (for Inbox UI changes)
- Sources/SpinLabApp/Features/Library/** (for Library UI changes)
- Sources/SpinLabApp/Features/Workbench/** (for Workbench UI changes)
- Sources/SpinLabApp/UI/** (for shared UI components)

UI-only tasks must NOT modify parser/state/registry logic files, including:
- Sources/SpinLabApp/App/SpinLabAppState.swift
- Sources/SpinLabApp/Library/LibraryRegistryParser.swift
- any parser/registry logic under Sources/SpinLabApp/Library/**

If a request requires both UI and logic changes:
- stop and explicitly split into two tasks first
- complete UI and logic in separate rounds
- do not mix both in one round

Parser/state/registry logic changes must be:
- explicitly called out before implementation
- handled in a dedicated round

---

Separation rules:
- UI must not decide metadata ordering rules.
- Ordering/tokenization/normalization logic belongs to parser/model/service layers.
- When a change touches both UI and logic/storage, split into separate tasks and commits.
- Do not call business logic across layer boundaries directly. UI must not call services or repositories directly.
- Parser must not call Service or Repository. Service may call Repository as its orchestration layer.
- Side effects (file I/O, XLSX parsing, registry sync) must not occur inside @Observable state setters.
  - Trigger side effects from UseCases or Services called by coordinators.

---

New feature sequencing policy (required):
When adding any new feature, implement only the layers that require change, in this order:
1. Domain model change (Domain/ or LibraryModels.swift) — if domain types are affected
2. Repository/persistence support — if new data needs to be stored or streamed
3. UseCase/Service logic — if business workflow changes
4. UI last — always last
Do not implement steps out of order. Skip steps only when that layer genuinely has no change.

---

Naming convention (required):
- Files: FeatureView.swift, FeatureViewModel.swift, ActionNameUseCase.swift, ServiceNameService.swift, NameStore.swift.
- Test files: V{major}{minor}{patch}FeatureNameTests.swift (e.g., V221DrawerMatchEngineTests.swift).
  - Tests added for a version bump must carry that version prefix.
- @Observable classes: final class, PascalCase.
- Capability protocols: suffix with Capability or Providing (e.g., RoutePlanningCapability, RegistrySubstrateRuleProviding).
- Do not suffix domain enums with Type or Kind unless already established (MeasurementType, WorkflowKind are existing exceptions).

---

Testing policy (required):
- New features added in version vX.Y.Z must have a corresponding VXYZFeatureNameTests.swift test file.
  - If the user has explicitly prohibited a version bump for this session, use the current version prefix instead.
- Parser and matching logic tests must use concrete input/expected-output pairs, not mocks.
  - Do not mock FilenameRuleParser, DrawerMatchEngine, or SpinLabRoutePlanner in tests.
- UseCase tests must pass real or fixture repositories, not mocks.
- Test files live in Tests/SpinLabAppTests/. Do not place tests near source files.

---

Architecture principle:
Add features through extension modules:
workflow
analysis module
metadata
view

Global shell layout policy:
- Use a stable three-column app shell as default:
  - left: navigation (Inbox / Workbench / Library, with room for future secondary menu)
  - center: workspace/actions (load/create/save/refresh/review and other primary operations)
  - right: inspector/output (details, plots, metadata, previews)
- Keep critical workflow actions in the center workspace column; avoid making the right column the primary action surface.
- Keep right column reusable across modules (sample detail now, plot/result/detail panels later).

---

Build and version policy (required):
- Every functional change must bump `Sources/SpinLabApp/App/AppVersion.swift` (`AppVersion.library`), unless the user explicitly instructs otherwise for that session.
- `[HARD][must]` Every round of code changes must end with executing `./scripts/build_desktop_app.sh debug` to rebuild and overwrite `/Users/jack/Desktop/SpinLab.app`. This is a sign-off gate — the round is not complete until the build succeeds.
- Do not skip desktop overwrite unless user explicitly asks not to.

---

Communication/reporting policy (required):
- Inherits global rules (role definition, functional language, no technical decisions to user).
- SpinLab-specific: when reporting Git actions, use plain human language first.
- Avoid raw shorthand-only status lines like `pushed branch`, `PR created` without context.
- Preferred style example:
  - "代码已经推到远端分支 `xxx`，并创建了 PR：`<url>`。"

---

Knowledge accumulation policy (required):

Session startup rule:
- `[HARD][must]` On entering the project, read `docs/philosophy.md` and `docs/features.md` to establish baseline context.
- `[DIRECTION][should]` When the task involves architecture changes, also read relevant devlog entries from `docs/history/`.
- `[DIRECTION][should]` Check `docs/known_issues.md` when modifying code in an area flagged there.

Session closeout rule (event-driven — only when substantive changes occurred):
- `[HARD][must]` After code changes, walk through this judgment tree:
  1. Did user-visible feature behavior change or get added? → Update the relevant section in `docs/features.md`.
  2. Was there a version bump or significant feature/architecture event? → Add a devlog entry in `docs/history/` and update the Development Log table in `docs/README.md`.
  3. Did the user express a new development preference or design philosophy? → Update `docs/philosophy.md`.
  4. Were known issues resolved or new ones discovered? → Update `docs/known_issues.md`.
  5. Is there a cross-session-relevant user preference? → Write to memory system.
- Skip steps that do not apply. Do not mechanically execute all steps every time.

Change impact rule:
- `[HARD][must]` Before modifying code, check `docs/features.md` for **invariants** listed under the affected workflow. If a proposed change would violate an invariant, stop and flag it to the user before proceeding.
- `[DIRECTION][should]` After completing a code change, verify that no invariant in `docs/features.md` was broken by the change.

Cross-review protocol — SpinLab specifics (required):
- Full protocol inherited from global `~/.claude/CLAUDE.md`. SpinLab-specific additions below.
- Design review trigger criteria for this project:
  - Touches 2+ architectural modules or crosses layer boundaries
  - Introduces a new pattern, protocol, or structural convention
  - Changes persistence format or domain model shape
  - Modifies CLAUDE.md rules or docs/ architecture specs
- Exception: purely mechanical and contained changes (typo fixes, single-file edits within one module, documentation content updates with no new rules) skip design review.

Roadmap reference (required):
- Active roadmap: `docs/V5_ROADMAP.md`.
- When discovering a bug or tech debt during development, append it to the matching version segment as an unchecked item.
- When unsure which segment, ask the user.
- Do not reorder or reprioritize existing items unless the user instructs.

Documentation directory structure:
- `docs/V5_ROADMAP.md` — Active 5.x roadmap (version segments as collection bins).
- `docs/philosophy.md` — Developer philosophy, habits, and collaboration preferences.
- `docs/known_issues.md` — Intentional behaviors, documentation inconsistencies, deferred items.
- `docs/features.md` — Feature invariants and test status for all areas (Inbox/Library/Workbench/Shared).
- `docs/history/<version>_<event>.md` — Event-driven development log entries (indexed in `docs/README.md`).
