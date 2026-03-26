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

---

Instruction priority policy (required):
- User explicit instructions are always the highest-priority requirement for implementation behavior.
- Do not introduce or apply self-defined rules unless the user explicitly requests them.
- Do not modify docs (including UI/design rules) unless the user explicitly requests doc updates.

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
- Use @Observable final class for all observable state objects.
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
- After each version bump and feature change, rebuild and overwrite desktop app for QA using:
  - `./scripts/build_desktop_app.sh debug`
- Default output app path:
  - `/Users/jack/Desktop/SpinLab.app`
- Do not skip desktop overwrite unless user explicitly asks not to.
- Acceptance default:
  - After a version iteration update, always overwrite `/Users/jack/Desktop/SpinLab.app` so user can validate directly from Desktop.

---

Communication/reporting policy (required):
- When reporting Git actions to the user (commit/push/PR), use plain human language first.
- Avoid raw shorthand-only status lines like `pushed branch`, `PR created` without context.
- Preferred style example:
  - "代码已经推到远端分支 `xxx`，并创建了 PR：`<url>`。"
