# SpinLab UI Rules

Status: active

This file supersedes legacy `UI_RULES.md` and is the active UI rule contract.

## Layout rule
- Prefer stable three-column shell:
  - left: navigation
  - center: operations/workspace
  - right: inspector/output

## Inbox V2 interaction rule
- Center column uses functional blocks in order:
  - Registry
  - File
  - Selection Workbench (inside File block)
- `File` block includes:
  - Actions (`Import Files`, `Recompute Route`, `Clear Imports`)
  - Pending Queue (status filters + file list + file path)
  - Selection Workbench (deposit mapping + file tags + draft actions)
- Standalone `Routing Review` and standalone `Apply` side blocks are removed.
- Right column is intentionally blank placeholder space for future modules; it is not an active inspector in the current Inbox design.
- Parsed values and manual confirmation actions happen in center-column `Selection Workbench`.
- `Create Project` is not part of Inbox primary workflow controls.
- `Clear Imports` must require explicit confirmation and must indicate it only clears pending/unarchived temporary items.

## Readability and density
- Preserve full filename/path readability on primary workflow surfaces.
- Favor structured metadata inspection over decorative spacing.
- In small windows, use wrapping and scroll access instead of clipping.
- Minimize repeated or low-value information; avoid showing the same facts in multiple blocks unless each placement has a distinct decision-making purpose.

## Safety and interaction clarity
- Major destructive actions require explicit confirmation.
- UI should clearly separate library-matched and review-required states.
- UI-only tasks must not alter parser/state/store behavior.

## State visibility consistency
- UI logic must be user-perspective-first: visible state is the source of truth.
- Do not split "visual state" and "internal state" for the same interaction contract.
- If a section appears collapsed to the user, its persisted/runtime expansion state must also be collapsed.

## Disclosure / collapsible section hit area
- All DisclosureGroup (or manual chevron toggle) labels must have a full-width hit area: clicking anywhere on the header row toggles expand/collapse, not only the chevron icon.
- Implementation: label HStack must include `Spacer()` + `.frame(maxWidth: .infinity)` + `.contentShape(Rectangle())` to extend the tappable region across the full row width.

## Column layout (v4.1.19+)
- All area views (Inbox / Workbench / Library) must use `AppColumnShell` for双栏布局（sidebar + content pane），不得直接写 HSplitView + 硬编码 frame。
- 列宽约束集中定义在 `ColumnDefaults` 的静态属性中。
- 左列宽度通过 `@AppStorage` 持久化，用户拖拽后关闭 app 重启恢复。
- `WorkflowWorkspaceShell` 是 `AppColumnShell` 的薄封装，Workbench 子视图通过它接入。

## Hover popover 交互合约 (v4.1.19+)
- 所有 hover 触发的 popover 必须使用 `HoverPopoverModifier`（`.hoverPopover()` modifier），不得各自实现 hover/dismiss 逻辑。
- 默认参数：showDelay 1s，dismissDelay 500ms。
- 鼠标离开触发元素后有 dismissDelay 窗口期，期间鼠标进入 popover 则保持。
- popover 内有确认弹窗（如删除确认）时 popover 不得关闭。
- 调用方可通过 `onPresentedChanged` 回调响应弹出/关闭事件（如 highlight 背景色）。

## Library detail section 顺序 (v4.1.19+)
当前固定顺序（非编辑模式）：
1. Sample Primary（基本信息）
2. Pending Changes（有变更时才显示）
3. Numeric Tags（有数据时才显示）
4. Measurement Data
5. Measurements Done
6. Metadata
