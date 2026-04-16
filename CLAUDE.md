# Agent Instructions

> This file contains cross-project engineering methodology and AI strategy.
> Project-specific details live in `specs/` — see Project Reference section at the end.

---

## Instruction Priority (required)

- User explicit instructions are always the highest-priority requirement.
- Do not introduce or apply self-defined rules unless the user explicitly requests them.
- Do not modify docs unless explicitly requested — exception: knowledge accumulation closeout (see below).

---

## Engineering Quality (required)

- `[HARD][must]` All implementations must follow first-principles reasoning. No redundant, decorative, or non-functional code.
- `[HARD][must]` Prefer long-term maintainability over short-term convenience.
- `[HARD][must]` Sign-off criteria: structural quality + maintainability + testability, not just feature correctness.
- `[HARD][must]` Do not rename, remap, or reformat any user-defined display name, ID, field name, or configuration value unless the user explicitly requests it. "Cleanup" or "normalization" of user-chosen names is forbidden.
- Execution gate and collaboration model: inherited from global `~/.claude/CLAUDE.md`.

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

- All runtime dependencies with side effects declared in AppEnvironment.
- Prefer capability protocols over concrete types.
- UseCases: stateless structs, receive dependencies as function parameters.
- AppState stores AppEnvironment fields as `@ObservationIgnored private` properties.
- Exception: read-only, side-effect-free singletons may be called directly.

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
- Domain models live in `Domain/`. Do not define inside `Features/`.
- Use `enum` for closed-set values. Never String constants.
- Raw models carry source data only. UI projections are separate presentation structs.

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
- `[DIRECTION][should]` Read relevant `docs/history/` entries for architecture tasks.
- `[DIRECTION][should]` Check `docs/known_issues.md` when modifying flagged areas.

### Session Closeout (event-driven)
- `[HARD][must]` After code changes, walk through:
  1. User-visible behavior changed? → Update `docs/features.md`.
  2. Version bump or architecture event? → Add `docs/history/` entry + update `docs/README.md`.
  3. New development preference? → Update `docs/philosophy.md`.
  4. Known issues resolved or discovered? → Update `docs/known_issues.md`.
  5. Cross-session user preference? → Write to memory system.
- Skip steps that don't apply.

### Change Impact
- `[HARD][must]` Before modifying code, check `docs/features.md` invariants. If a change would violate one, flag it before proceeding.

---

## Roadmap Reference

- Active roadmap: `docs/V5_ROADMAP.md`.
- Discovered bugs/debt: append to matching version segment.
- Do not reorder/reprioritize unless user instructs.

---

## Project Reference (SpinLab-specific)

Project-specific architecture, code placement, module contracts, and checklists are in:
- `specs/06_PROJECT_ARCHITECTURE.md` — code placement, canonical implementations, Workbench Shell, Import pipeline, extension modules, change boundaries, pre-merge checklist, temporary exceptions, build policy
- `specs/04_UI_RULES.md` — visual rules (fonts, spacing, buttons, disclosure sections, accessibility)
- `specs/01_PRODUCT_RULES.md` — product behavior contract
- `specs/02_DATA_RULES.md` — domain model and data rules
- `specs/03_PARSER_ROUTING_RULES.md` — import parse/routing rules

Read the relevant spec when the task touches that area. Do not read all specs every session.
