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

## 审计结果（初版，基线 `adc30022`，静态读码；未跑 GUI、未跑 CI）

路径前缀 Sources/SpinLabApp/。数字来自 grep 与 `scripts/ui_rules_baseline.json`，行号以该基线为准。

### A. 折叠：规则、组件、检查三者不一致

- 规则（04_UI_RULES「Disclosure Sections」）：所有折叠头必须用 `CollapsibleSectionHeader`；不得新建手写 chevron+HStack。
- 组件：`UI/CollapsibleSectionHeader.swift`（29 行，Button + 全行 contentShape），已被 5 个文件使用：LibraryV2AssetsSection、InboxOperationPanel、LibraryWorkspaceSections（4 处）、LibraryDeletionConfirmationSheet，以及 Library 设置/搜索区。
- 现实：仍有 `DisclosureGroup(` 调用 9 处，全部在 Features 内且全部在基线中：Create Sample 与 Edit Batch 的 RHEED 各 1、LibraryDetailView Metadata 1、LibraryMeasurementsDoneSection 4、MeasurementDataSectionView 1、WorkbenchWarningPanel 1。基线合计 10 = 这 9 处 + RecomputePreviewPanel 的手写 chevron 折叠头 1 处。
- **绕过方式不是"没用组件"，而是用 `DisclosureGroup` 加 `.onTapGesture { isExpanded.toggle() }` 补全行点击**：LibraryMeasurementsDoneSection.swift:284 与 :611（`disclosureLabel`，注释写明"macOS DisclosureGroup 只响应 chevron 点击"）、MeasurementDataSectionView.swift:44、LibraryDetailView.swift:200。同一个点击范围问题被各处手工补丁重复修，这是 #236 点击范围问题能重复出现的直接原因。
- 守卫缺口：`disclosure-group` 规则只匹配 `DisclosureGroup(`，以及同一行上同时出现 `chevron.down` 与 `chevron.right` 的写法。因此它拦得住新增 DisclosureGroup，但拦不住：①不含 DisclosureGroup 的手写折叠，如 Button + 单个三元 chevron 分写多行，或 `chevron.up`/`chevron.down` 组合（`RuleExpandableRow.swift:76`，整行可点的展开行，语义是行展开而非 section 头，不一定该迁移）；②新增的 `.onTapGesture { …isExpanded.toggle() }` 手写折叠头。
- 守卫范围：只扫 `Sources/SpinLabApp/Features`，不扫 `App/`、`UI/`、`Workbench/`。`App/SidebarTreeView.swift:55` 的 chevron 是树节点，不属于折叠 section，应列为合理例外。
- 结论：组件本身够用且已验证；缺的是 ①DisclosureGroup 的迁移（基线 10 处，应逐个判断是 section 头还是树/行展开）；②能容纳"标题右侧带计数徽标"（`disclosureLabel` 带 count capsule）这类需求，否则这几处迁移不了，补丁会继续存在。

### B. 弹窗：规则已写，实现靠各页面复制

- 规则（「Sheets and Dialogs」）：短表单按内容定高、无内层滚动；长表单固定标题与操作栏，仅中间滚动，高度为"自然高度与屏幕可见高度减去边距的较小值"；最小宽度而非固定高度。
- 实现：只有两处遵守"长表单"规则，且是复制粘贴：CreateNativeSampleSheetView.swift:132–140, 253, 361–366 与 EditBatchGrowthSheetView.swift:22–32, 141, 172–177。两处各自带一份 `SheetContentHeightKey`、`maxFormHeight`（公式相同 `screen - xxl*8`，下限 `xxl*10`）、`ScrollView + GeometryReader + frame(height: min(...))`。
- 已知缺陷（两份共有，修一处不会带动另一处）：①用 `NSScreen.main` 而不是弹窗所在屏幕，多屏下可能算错；②高度只在内容变化时通过 preference 更新，折叠 RHEED 展开后依赖 preference 重新触发，需实测；③固定的 `xxl*8` 边距是经验值，未考虑 Dock/菜单栏以外的情况。
- 其余 sheet 都不走这条路：LibrarySheets 的三个日志窗口用 `minWidth/minHeight` 固定下限；RegistryGrowthImportSheet 用 `minWidth: 800, minHeight: 470` 加 maxHeight 填满（复杂浏览器类，属合理例外）；LibraryDeletionConfirmationSheet（#236）为短确认框，直接渲染内容，宽度 380–480。
- 全库 `.sheet(` 16 处、分布在 10 个文件；`keyboardShortcut(.cancelAction)` 仅 5 个文件使用。大量 sheet 没有统一的 Cancel/Esc 行为，需要抽样确认是否属于缺陷，暂不下结论。
- 结论：这是唯一有明确重复且已造成问题的地方，值得提取；范围限定在"标题 + 内容 + 操作栏"版式，不接管业务状态。

### C. 按钮：规则与实际有分歧

- 规则：破坏性操作用 `.bordered + .foregroundStyle(.red)`，**不用** `.borderedProminent`。
- 实际：LibraryDeletionConfirmationSheet 的确认钮是 `.borderedProminent + .tint(.red) + role: .destructive`，违反字面规则。全库 `borderedProminent` 搭配红色的只此一例（grep 未发现第二处），其余 destructive 多用 `role: .destructive`，视觉由系统决定。
- 需要用户决定：改规则（允许"确认弹窗里的最终破坏性确认"使用 prominent 红色），还是改按钮。我的建议是改规则，只放宽到"弹窗中不可逆动作的最终确认"，理由是它是用户已验收的现状，且与 macOS 习惯一致。此项不影响组件设计，可单独决定。

### D. 守卫现状

- `ui_rules_check.py` 已有：4 条规则、per-file baseline 只降不升、`--base-baseline` 防止 PR 抬高基线、`test_ui_rules.sh` 自测、CI 工作流 `ui-rules-guard.yml`。基线合计：numeric-spacing 351、small-text 171、cjk-ui-literal 65、disclosure-group 10，共 59 个文件。
- 机制本身可靠，不需要新框架。缺口是规则覆盖面（见 A），而非机制。
- 04_UI_RULES 自己承认"sheet/窄窗口几何未机器检查"，这与审计一致。

### E. 测试：没有一个测弹窗几何

- `NativeSampleUITests` 名为 UI 测试，实际是业务层测试加源码字符串断言（例如检查源文件包含 `CreateSampleSheet.Title`），不渲染视图，不测高度、滚动或按钮可达性。
- `ControlsSurfaceLayoutTests` 测的是 Workbench 控件的布局几何，范围是 Workbench，不涉及 sheet。
- 仓库里使用 `NSHostingView`/`ImageRenderer`/`fittingSize` 的测试有 5 个（AppWorkspaceShellContractTests、ControlsSurfaceTestSupport 等），说明"在测试里渲染视图并量尺寸"这条路在本仓库可行，可复用其支持代码。
- 弹窗唯一的真实验收途径是 GUI 测试 VM（见 CLAUDE.md 的 spinlab-gui-validation）。#236 的问题都是靠这条路发现的，成本高、只能人工触发。
- 结论：布局测试是净新增能力；先在公共 sheet 布局上做一组轻量几何测试（短/长内容、展开收起），不强制所有 sheet。

### 初步取舍（供 reviewer 质疑，不是最终方案）

1. 提取公共自适应 sheet 布局，仅替换 Create Sample 与 Edit Batch，作为第一批；两处重复和两项共有缺陷可一起收掉。
2. 折叠：扩展 `CollapsibleSectionHeader` 支持尾部附加内容（如计数徽标），再逐处迁移基线内的 DisclosureGroup；先迁移用 `onTapGesture` 补丁的 4 处，因为它们正是点击范围问题的来源。
3. 守卫：只补一条 `onTapGesture` + `isExpanded.toggle()` 的检测；不新建规则框架。
4. 按钮、表格、列表：审计未发现重复实现带来的实际问题，本轮不提取。
5. 规则分歧（C）等用户决定。

### 尚未核查（诚实列出）

- 其他 sheet（RulesPanel、WorkflowGallery 等）是否有未被 grep 覆盖的高度/滚动写法。
- 多屏下 `NSScreen.main` 的实际行为、展开 RHEED 后的实际高度更新：未在真实窗口验证。
- Inbox、Workbench、Publish 区域的重复 UI：本稿只深入了 Library 与折叠/弹窗两条线。
- `WorkbenchWarningPanel` 的 DisclosureGroup 是 section 头还是面板内行展开，需读代码判断。

以上为静态审计初稿，未经独立 reviewer 审查，也未经用户确认；不代表设计已验收。
