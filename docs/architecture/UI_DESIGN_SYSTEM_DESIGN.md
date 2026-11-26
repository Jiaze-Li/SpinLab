# SpinLab UI Design System 收敛 — Design Draft

基线：main `adc300228f13023d26e235afa59519a9ec0a5b7b`（#236 已合并，用户实际 GUI 验收通过）。2026-11-26 用户同意先开独立设计 PR，暂不实施；本稿是现状审计与设计任务的入口，不是新的规范权威、技术债看板或代码实施授权。

## 目标与边界

让符合规范的 UI 成为默认实现：相同行为有一个适当的公共实现，设计规则有唯一权威，重复发生的可检查违规由现有机制阻止，真实交互通过验收。保持科研信息密度、macOS 原生交互、业务能力和现有布局语义；不要求所有页面长得一样。遵守 04_UI_RULES 的 proportional governance：只有重复使用或反复出现的缺陷证明收益时才提取组件或增加检查。

- 全局规则仍以 [04_UI_RULES](../../specs/04_UI_RULES.md) 为唯一权威，Workbench 控件组织仍归 [06_WORKBENCH_CONTROLS_UI](../../specs/06_WORKBENCH_CONTROLS_UI.md)，图形科学呈现遵循 05_PLOT_RULES；公共 token/组件是规则的代码实现。不得另建一份相互冲突的设计规范。
- 本轮以桌面 SwiftUI 为范围；手机和 Web 的既有规则不变，避免将桌面布局强行移植。业务状态、数据安全、存储、科研算法、Task 6/7/12/11 不在范围内。
- 本 PR 先审计、比较方案、明确最小公共接口与实施/验收顺序；不改 Swift、测试、CI、正式 Library，不直接合并或实施。

## 已核实的起点（静态代码事实，不代替完整审计）

| 领域 | 当前实现与证据 | 本轮需要回答 |
|---|---|---|
| Token 与基础组件 | `UI/AppSpacing.swift`、`AppFontScale.swift`、`WorkbenchUIStyle.swift`、`MetadataViews.swift`、`FlowLayout.swift`、`AppWorkspaceShell.swift` 等；04_UI_RULES 已列出共享组件 | 哪些规则已由公共 API 保证，哪些仍依赖调用者？不要重建已有能力 |
| 折叠 | `UI/CollapsibleSectionHeader.swift` 使用 Button + 全行 contentShape；#236 的 Details 已改用它，用户验收通过 | 是否存在绕过入口、状态/键盘/命中范围问题；现有组件是否足够，不预设替换 |
| 弹窗 | CreateNativeSampleSheetView.swift:132–140, 253, 361–366 与 EditBatchGrowthSheetView.swift:22–32, 141, 172–177 分别测量内容高度并以屏幕高度限制中间 ScrollView；各有局部 PreferenceKey。#236 的 LibraryDeletionConfirmationSheet.swift:106–132 现直接渲染内容（此前 ViewThatFits + ScrollView 导致短弹窗滚动，已修复） | 是否能用一个轻量公共布局解决短/长表单和内容动态变化，不复制各页面状态和业务逻辑 |
| 按钮、表格和列表交互 | 04_UI_RULES 的 Button Style、VC-4/5/7、信息非冗余与可访问性已有明确约束；#236 删除按钮使用 borderedProminent + red tint，与现行 destructive 样式条款存在差异 | 核实现有规范、实际语义和消费者；原生控件足够则不包一层，必要时再提出规则修订供用户确认 |
| 自动约束 | `scripts/check_ui_rules.sh` → `ui_rules_check.py`，现查 numeric-spacing / small-text / cjk-ui-literal / disclosure-group，旧违规按 per-file baseline 限增；`test_ui_rules.sh` 自测。Workbench 另有 controls contract AST 检查 | 区分可靠可静态检查的违规与实际几何/语义；查现有 guard 的作用域、漏检、误报和 baseline，不另起一套检查框架 |
| 实际验收 | `ControlsSurfaceLayoutTests.swift`、`NativeSampleUITests.swift` 等现有测试入口；04_UI_RULES 要求 sheet/dialog 真屏验收。#236 实际发现过点击范围、展开裁切、短弹窗滚动问题 | 核实测试究竟测了什么；区分静态检查、布局测试、真实交互，禁止将编译通过或名为 UI 的测试冒充真实 GUI |

路径以 Sources/SpinLabApp/ 为 Swift 源码前缀；上表是核查起点，不是全项目组件清单。

## 设计任务（先做调查，再给出推荐）

1. **现状与覆盖矩阵。** 以实际源码为准，跨 Library、Inbox、Workbench、Rules、Publish 和 App/UI 公共区核查相同交互的不同实现；按规则 → 权威 token/组件 → 主要消费者 → 已有检查与验收 → 缺口组织。盘点普通 sheet、长表单、短确认框及必要的复杂浏览器例外，定位重复代码、已发生问题与有意义的风险；不要把每个 SwiftUI 控件都算成设计债。注明基线与源码证据。完整技术债生命周期只在 shared TASK_BOARD；本稿不得另建 tracker。
2. **最小公共组件边界。** 优先评估共用自适应 sheet 布局（标题、业务内容、操作区的布局责任；业务事件、确认计划、错误和状态归 feature）。短内容不滚动，展开/收起自动增减高度，真正超出当前屏幕可用高度才限制中间滚动区，按钮始终可达；长文件名/字段换行，避免双层滚动。核实多屏与小窗口、焦点和键盘行为。比较直接复用既有模式、轻量共享布局、扩大公共组件三条路线的成本与收益，推荐最小可行方案。已有 CollapsibleSectionHeader 继续作为折叠入口；按钮、行点击、信息展示只有足够证据才进一步公共化。保留合理的 native alert/confirmationDialog 和复杂数据浏览窗口，不一刀切套壳。
3. **规范的执行路径。** 确定哪些要求用 token/组件直接保证，哪些用现有 UI Rules Guard（必要时复用已有 AST 能力）可靠拦截，哪些必须由布局测试或实际 GUI 验证。已有公共入口足够时不得重新实现相同交互；若不足，先评估扩展，允许有证据的业务例外。不增加重复规范、无法维护的通用 AST 框架、全库硬性视觉相等检查或大量假阳性规则。既有违规 baseline 以当前 main 实测为依据，严禁为新增违规抬高 baseline。建议未来在 AGENTS 的既有 UI 入口中链接明确组件/规范，具体改法待审查。
4. **验证及渐进实施计划。** 优先用 #236 删除弹窗和 Create Sample / Edit Batch 的真实消费者检验设计。定义短/长内容、动态折叠、狭窄窗口、长文件名、真实点击整个标题/键盘操作、危险动作取消/确认、错误可见与所有操作可达等验收场景；保留 V1/V2 功能、Workbench 控件现有合同与数据安全。优先扩展有用的现有测试，说明真实 GUI 验收的边界与证据；不为所有页面强制截图比对。后续实施按收益分批，先用现有消费者验证再推广，无需一次性重构所有旧页面。

## 设计评审交付

- 用可追溯源码证据说明现有体系为何会让 #236 的问题重复发生；列出哪些已经有效、哪些仍需要收敛。
- 提交最小公共组件的职责/接口草案、复用约束、适用范围与例外；明确哪些规则无需改、哪些确实需要用户决定。
- 给出自动检查和实机验收各自能证明的内容、覆盖范围与增量成本；避免把所有规则机械地变成 CI。
- 给出小批次实施顺序、回归验证和停止条件；不以组件数、删掉多少文件或新增多少规则为目标。
- 设计由独立 reviewer 质疑并由用户确认后，才在后续实施阶段改变实际代码；当前 Draft 不代表审计、设计或实施已验收。

当前只提交上述设计入口及已核实的起点；完整现状审计、接口设计、方案取舍和独立审查仍待完成。
