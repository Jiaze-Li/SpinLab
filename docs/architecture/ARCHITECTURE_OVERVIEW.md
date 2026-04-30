# SpinLab Architecture Overview

This document explains the current architecture for human readers.

## High-level shape

SpinLab is organized around three feature domains:
- Inbox
- Library
- Workbench

Runtime flow is:
- Import -> Confirm -> Visualize -> Analyze -> Save -> Archive

`SpinLabAppState` acts as the app shell and coordinator.
Feature state and single-domain behavior live in FeatureStores.

## Layer boundaries

Core layering:
- Input/Files
- Parser/Import pipeline
- Domain model
- UseCase/Service/Orchestrator
- Repository/Store (I/O and persistence)
- AppState / FeatureStore state surface
- View / ViewModel

Design intent:
- Keep business logic out of Views.
- Keep storage and file I/O out of UI state objects.
- Keep parser/routing boundaries explicit and testable.

## App shell responsibilities

`SpinLabAppState` should mainly do:
- Cross-feature coordination (Inbox <-> Library <-> Workbench)
- Global concerns (navigation, alerting, audit context)

`SpinLabAppState` should avoid accumulating single-domain details that belong inside a FeatureStore.

## FeatureStore responsibilities

FeatureStores hold:
- Domain-scoped observable state
- Domain methods (single-feature operations)
- Projection subscriptions for their own repositories/streams

FeatureStores should expose explicit outcome-based methods for complex operations where useful.

## UseCase and Service split

UseCase:
- Stateless input/output business operation
- Easy to unit test in isolation

Service/Orchestrator:
- Stateful or multi-step domain orchestration
- Coordinates multiple lower-level operations in one domain

## Presentation-only container exception

Not every state holder must be an observable class.
A tiny presentation-only container with no autonomous behavior may stay as a value type (`struct`) if this reduces complexity.

## Current migration direction

Current direction is to keep slimming `SpinLabAppState` toward an app-shell role by:
- Moving single-domain methods into the corresponding FeatureStore
- Removing compatibility passthrough properties once views/tests migrate to namespaced access
- Preserving strict boundaries across Import pipeline stages

## Temporary exceptions (migration seam)

Some transitional seams still exist while refactor is in progress.
These are temporary and should shrink over time, not expand.

Operational rules for contributors/agents:
- Do not add new compatibility passthrough properties on `SpinLabAppState`.
- If you touch a migration seam, prefer reducing it in the same change.
- New single-domain behavior must still be implemented in FeatureStore.

## UI Shell Architecture (v4.1.19+)

### RootSplitView — 条件渲染

`RootSplitView` 使用 `NavigationSplitView`（sidebar + detail）。detail 区域通过 `switch appState.selectedArea` 条件渲染，只有当前活跃 area 的 view 在 view tree 中。切换 area 时旧 view 销毁，新 view 重建并通过 `InteractionSnapshot` 恢复状态。

设计决策：不使用 ZStack + opacity 保活模式，因为 macOS 的 NSTrackingArea 无法被 `allowsHitTesting(false)` 屏蔽，隐藏面板的 hover 事件会泄漏。

### AppColumnShell — 统一两列布局

所有 area 的两列布局（左栏操作区 + 右栏展示区）统一使用 `AppColumnShell`（`Sources/SpinLabApp/UI/AppColumnShell.swift`）。

- `ColumnDefaults` 集中定义每个 area 的列宽约束（min/ideal/max）
- 左列宽度通过 `@AppStorage` 持久化，key 格式 `splitView.{area}.leftWidth`
- GeometryReader 追踪实际宽度，节流 + clamp 后写入
- `WorkflowWorkspaceShell` 是薄封装，内部转发到 `AppColumnShell(columnKey: "workbench")`

### HoverPopoverModifier — 统一 Hover Popover 交互

所有 hover 触发的 popover（Library measurement 行、Workbench chart canvas）使用统一的 `HoverPopoverModifier`（`Sources/SpinLabApp/UI/HoverPopoverModifier.swift`）。

行为合约：
- `showDelay`：鼠标停留多久后弹出（默认 1s）
- `dismissDelay`：鼠标离开后多久关闭（默认 500ms），期间鼠标进入 popover 则保持
- Panel hover tracking：鼠标在 popover 上时不关闭
- Dialog guard：popover 内有确认弹窗时不关闭
- `onPresentedChanged`：弹出/关闭时通知调用方（用于 highlight 等）

### InteractionSnapshot 状态持久化

切换 area 时 view 销毁，以下状态通过 `InteractionSnapshot` 持久化并在 `onAppear` 恢复：

| 状态 | 归属 | 持久化方式 |
|------|------|-----------|
| Inbox fileFilter | InboxInteractionState.fileFilter (String?) | onChange + onDisappear |
| Library disclosure 展开 | LibraryView @State → Binding → LibraryInteractionState | interactionStateSnapshot 计算属性 |
| Library search 参数 | LibraryInteractionState (11 个 text + hasExecuted) | 已有 |
| Workbench 分析状态 | FeatureStore（不在 @State） | 不需要 view 级持久化 |

## Code Placement

| Code shape | Destination |
|---|---|
| New observable feature state | FeatureStore in `Sources/SpinLabApp/App/State/` |
| Cross-feature coordination | `SpinLabAppState` methods |
| Complex operation within a single feature | FeatureStore method returning `Outcome` enum/result |
| Stateless business operation (Input → Output) | `Sources/SpinLabApp/UseCases/` struct |
| Stateful domain service/orchestration | Service/Orchestrator in `Sources/SpinLabApp/App/` or domain module |
| External I/O (filesystem/persistence) | Repository/Store layer |
| Filename parsing/matching/routing rules | `Sources/SpinLabApp/Import/` pipeline layers |
| Pure UI interaction state (expand/collapse/filter text) | `FeatureViewModel` |
| New workflow workspace store | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceStore.swift` conforming `WorkbenchWorkspaceProviding` |
| New workflow workspace view | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceView.swift` wrapping `WorkflowWorkspaceShell` |
| New workflow ingestion UseCase | `Sources/SpinLabApp/UseCases/Ingest<Name>SelectionsUseCase.swift` |
| New workflow pack contracts | `Sources/SpinLabApp/Workbench/V3/<Name>PackContracts.swift` (`PackConfig` + `PackResult`) |
| New workflow ingestion contracts | `Sources/SpinLabApp/Workbench/V3/<Name>IngestionContracts.swift` |

## Canonical Implementations (reference)

- Feature Store pattern: `Sources/SpinLabApp/App/State/InboxFeatureStore.swift`; `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift`
- UseCase (sync flow): `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift`
- UseCase (non-fatal error channel): `Sources/SpinLabApp/UseCases/SaveLibrarySampleEditsUseCase.swift`
- Apply / archive orchestration (Service layer): `Sources/SpinLabApp/App/ApplyCoordinator.swift`; `Sources/SpinLabApp/App/InboxArchiveApplyService.swift`
- Repository + AsyncStream projection: `Sources/SpinLabApp/Repositories/DomainRepositories.swift`
- Workbench Shell + WorkspaceStore pattern: `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift`; `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` (most complete reference)

## Import Pipeline (5-stage boundary)

- `Parse/` — filename tokenization only. No routing decisions.
- `Route/` — generate RoutePlan candidates only. No final verdict.
- `Match/` — library drawer matching only. No UI projection.
- `Evaluate/` — compute final RouteStatus verdict only. No direct UI output.
- `Presentation/` — convert routing data to UI structs only. No business logic.
- `InboxRoutingState` is the only facade connecting the routing pipeline to AppState.

Details: `docs/architecture/inbox/ROUTING_PIPELINE.md`

## Related docs

- Routing pipeline: `docs/architecture/inbox/ROUTING_PIPELINE.md`
- Workbench shell and adding new workflows: `docs/architecture/workbench/EXTENSION_BOUNDARIES.md`
