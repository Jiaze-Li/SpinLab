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

### 补查结果（第二轮，同一基线）

- 其余 sheet：LibrarySheets 三个日志窗口、SamplePlotsGallerySheet、RegistryGrowthImportSheet 都是 `minWidth/minHeight` 的浏览器/日志类窗口；WorkflowSection 的 Add Workflow 是 360 宽的短表单，已有 `cancelAction`/`defaultAction`。**除 Create Sample 与 Edit Batch 外，没有第三个"自量高度 + 限高滚动"的长表单。** Features 内 `PreferenceKey` 仅这两处使用；`GeometryReader` 在 WorkflowWorkspaceLeftColumn、LibraryDetailView 是布局用途，不是 sheet。
- Inbox、Workbench、Publish：没有 `.sheet(`（Workbench 仅两个 popover）；Inbox 的折叠已用 `CollapsibleSectionHeader`（`InboxOperationPanel.swift:220`）。Publish 目录无 sheet 或折叠。**本轮无需扩大到这三个区域。**
- `WorkbenchWarningPanel.swift:28`：`DisclosureGroup` 的 label 是"图标 + 标题 + 数量"，属 section 头，可在组件支持尾部内容后迁移；但它在 Workbench 底部窄面板内，迁移前需确认视觉不变。
- 键盘行为：Create Sample / Edit Batch / Add Workflow 的主按钮是 `.defaultAction`；删除确认弹窗的确认钮**没有** `.defaultAction`，只有 Cancel 绑定 `.cancelAction`，即回车不会触发删除，现状符合"避免默认触发不可逆删除"。

### 设计决策（吸收外部审阅意见后的当前方案，仍待独立 reviewer 与用户确认）

范围收敛为：两项公共组件建设（折叠头扩展、自适应 sheet 布局）+ 一项验证能力（sheet 几何测试）+ 现有治理的增量完善。

**1. 折叠：统一行为，不统一所有展开操作。**
- 给 `CollapsibleSectionHeader` 增加可选的非交互 `trailing` 内容槽（`@ViewBuilder`，默认空），而不是专门的 `count` 参数。计数、状态、简短说明都走同一入口，避免每种需求再改公共组件。
- 不改默认外观；现有 5 个文件的调用不变。
- 迁移按语义分类，不为清零基线而迁移：
  - Section 头 → 迁移：LibraryMeasurementsDoneSection（4 处，含 `onTapGesture` 补丁）、MeasurementDataSectionView、LibraryDetailView Metadata、WorkbenchWarningPanel、两处 RHEED、RecomputePreviewPanel 的"无变化"头。
  - 树节点（SidebarTreeView）、整行展开行（RuleExpandableRow）、"View All ›"链接 → 不是 section 折叠，不迁移，记为例外。
- 迁移要点：`DisclosureGroup` 自带的展开动画与缩进由调用方在 `if isExpanded` 内自行维持；每处迁移前后需保持展开状态持久化语义（如 `state.isMetadataSectionExpanded`）。

**2. 弹窗：`AdaptiveSheet`（名称待定）的职责与接口草案。**
- 只负责版式：固定标题区、中间内容区、固定操作区；内容短则不滚动，内容变高（如展开 RHEED）自动增高，超过窗口所在屏幕可用高度才让中间区域滚动。业务状态、校验、确认计划、错误展示、按钮行为全部留在调用方。
- 接口草案（实施阶段再定细节）：`AdaptiveSheet(minWidth:) { 标题 } content: { … } actions: { … }`。
- 实现要点：用 `onGeometryChange`（工程已在 WorkflowWorkspaceLeftColumn 使用，部署目标 macOS 14）取内容自然高度；上限取内容所在**窗口的屏幕**可用高度减去标题、操作区与边距，取不到窗口时才回退 `NSScreen.main`；不使用 `ViewThatFits + ScrollView`，因为 #236 已证明它会让短弹窗出现多余滚动。
- 不丢失输入状态和焦点：内容区在滚动与非滚动形态之间不得重建视图身份（不用 `if needsScroll { ScrollView{…} } else {…}` 两套分支），实施时用单一 `ScrollView` + 高度上限，或以 `.scrollBounceBehavior(.basedOnSize)` 等方式实现，并用测试验证。
- 删除确认弹窗：第一批**不迁移**，作为"短内容"验证对象——验证 `AdaptiveSheet` 能在不滚动的前提下容纳它；是否迁移待验证后再定。

**3. 规则修订（用户已于 2026-11-26 决定改规范、保留现有红色实心确认钮；04_UI_RULES 的实际修改留到批次 3）。**

| 场景 | 样式 |
|---|---|
| 普通破坏性操作 | `.bordered` + 红色 |
| 不可逆操作的最终确认弹窗 | 允许 `.borderedProminent` + 红色 |
| 语义 | 一律保留 `role: .destructive` |
| 键盘 | 不可逆确认钮不绑定 `.defaultAction`；Cancel 绑定 `.cancelAction` |

理由是危险操作的视觉语义和误操作风险（取消路径明确、回车不触发），而不是"符合 macOS 习惯"。

**4. 守卫：先迁移，再按真实绕过模式加规则。**
- 暂不增加 `onTapGesture + isExpanded.toggle()` 规则：该写法也可能用于合法的列表交互，误报风险高。迁移后若出现具体、高置信度的绕过模式，再增量加规则。
- 已知局限（不因此重建检查）：基线按"文件 + 规则"计数，同一文件内删一个旧违规、加一个新违规时数量不变，仍可通过；`--base-baseline` 只防总数被抬高。
- 主要治理手段是组件复用，CI 是防线，不是设计权威。

**5. 验证能力：sheet 几何测试，三个场景缺一不可。**

| 场景 | 验收 |
|---|---|
| 短内容（删除确认弹窗） | 内容高度 ≤ 可用高度时，无滚动，高度等于内容高度，两个按钮可见 |
| 动态内容（RHEED 展开/收起） | 展开后高度随内容增大、收起后回落；输入框内容与焦点不丢；展开头整行可点 |
| 超长内容（完整长表单、小屏） | 总高度不超过窗口所在屏幕可用高度；标题与操作区始终可见；仅中间滚动；长文件名换行，不出现双层滚动 |

- 三者都成立才证明布局解决的是公共问题，而不是把两份重复代码合并成一份。
- 自动化部分：在单元测试里用 `NSHostingView` 渲染并测高度，复用现有支持代码（见 E 节）；真实点击、窗口位置、多屏行为仍用 GUI 测试 VM 验证，并写明其证据边界。不做全库截图比对。

### 实施顺序与停止条件

1. **批次 1**：`AdaptiveSheet` + 几何测试（含删除确认弹窗的短内容验证）；迁移 Create Sample 与 Edit Batch。停止条件：任一场景不成立、焦点/输入状态丢失、或迁移后代码没有实质减少。
2. **批次 2**：`CollapsibleSectionHeader` 增加 `trailing`；迁移带 `onTapGesture` 补丁的 4 处与 RHEED 两处。停止条件：迁移后视觉或展开状态持久化语义改变，且无法在组件内保持。
3. **批次 3**：按迁移中发现的真实绕过模式补守卫；按删除按钮规则修订更新 04_UI_RULES 与删除确认弹窗，并链接 AGENTS 的 UI 入口。
4. 不推广到其余页面，除非批次 1、2 的真实消费者证明有收益。

### 仍未核查

- 多屏下 `NSScreen.main` 与窗口所在屏幕的实际差异；展开 RHEED 后高度更新的现状行为。以上需 GUI 实测，不能靠读码确认。
- 统计数字（grep 计数、基线合计）为作者读码所得，尚未被独立 reviewer 复核。

以上为设计草案，未经独立 reviewer 审查，也未经用户确认；不代表设计已验收。
