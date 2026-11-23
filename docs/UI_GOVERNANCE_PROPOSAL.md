# SpinLab UI Governance：规则制定与执行方案（讨论收敛稿 v0.2）

> Status: **Draft / proposal only（已收敛）**。本文件用于 PR #226 讨论与方案定稿，**本身不是长期并行的第二套规范**。本 PR 保持 design-only，不更改 UI、不修改已有规则的效力、不引入新 CI 阻塞项。Step 1 实施时将批准的原则直接写回 `specs/04_UI_RULES.md`。
>
> 基线：2026-11-23 的 SpinLab `main` 分支（`b65c5cee`）。

---

## 1. 核心设计哲学（写入 `04_UI_RULES.md` 顶部的指导原则）

> **SpinLab UI 以科学研究任务为中心，在保证关键内容可读、操作可达、信息层级清晰的前提下，提供尽可能高的有效信息密度。**
>
> 优先使用原生 macOS 交互与现有设计常量。布局应适应内容与容器真实可用宽度，不应强迫内容适应固定尺寸。统一的是设计逻辑和视觉语言，而不是每个界面的结构。
>
> 允许少量不影响使用的视觉差异。只有能明显降低重复缺陷、且维护成本合理的规则才值得自动化执行。

### 治理边界（不做清单）

- **不做 UI “准入锁”**：不要求开发前做机器化的“已读规范认证”，也不在发布时要求重新通读全部 UI 文档；沿用 `AGENTS.md` 按改动范围按需参考对应规范。
- **不引入强制性 UI 框架 / 不复制 Workbench 重型契约**：`06_WORKBENCH_CONTROLS_UI.md` 的强类型 DSL 与 AST 扫描仅适用于多 Plot Mode 共享的 Workbench 控件区；Library / Inbox 等普通界面优先使用原生 SwiftUI 与现有轻量 token（`AppFontScale`、`AppSpacing`、`FlowLayout`、`MetadataViews`）。
- **不搞运动式全仓 UI 翻新**：存量违规通过 `scripts/ui_rules_baseline.json` 锁定（只减不增），在后续触及对应模块时顺手清理。
- **暂不引入截图 CI**：视觉与窄窗布局验证在 Step 1 先通过本机桌面构建与真实窗口状态检验，不为低信噪比的自动截图对比增加 CI 维护负担。

---

## 2. 本地代码 Audit 确认的事实与修正

### 2.1 右侧 Detail（Inspector）栏的真实宽度约束与裁切根因
- **容器宽度事实**：[`WorkspaceLayoutState.swift`](../Sources/SpinLabApp/UI/WorkspaceLayoutState.swift) 定义三栏最小/理想宽度为 `leftMin = 180`、`centerMin = 420`、`rightMin = 320`（`rightIdeal = 420`、`rightMax = 720`），外加两条实际布局宽度为 9 pt 的分隔条（[`WorkspaceDivider.swift`](../Sources/SpinLabApp/UI/WorkspaceDivider.swift) 中 `thickness = 9`），三栏最小总宽为 **938 pt**（`180 + 420 + 320 + 2×9`）。当窗口总宽 `< 938 pt` 时，`layout(for:)` 将 `usable - 420` 平分给左右两栏，右侧栏会进一步窄于 320 pt；且 [`AppWorkspaceShell.swift`](../Sources/SpinLabApp/UI/AppWorkspaceShell.swift) 对三栏直接 `.clipped()`。
- **挂载在同一右侧栏的受影响视图**：
  1. **Sample Detail Header**（[`LibrarySampleDetailHeaderView.swift`](../Sources/SpinLabApp/Features/Library/LibrarySampleDetailHeaderView.swift)）：将标题 `Sample Detail` 与 4 个操作按钮（`Numeric日志`、`Metadata日志`、`Delete`/`Cancel`、`Edit`/`Save`）排在单行 `HStack`，在 320 pt 下必然挤压或裁切。
  2. **Sample Results**（[`SampleResultsSection.swift`](../Sources/SpinLabApp/Features/Library/SampleResultsSection.swift)）：单行 `HStack` 内硬编码 `minWidth: 180`（Label）+ `minWidth: 80`（当前值）+ `minWidth: 100`（输入框）+ `Confirm` + `Clear` + 间距，总宽超过 450 pt；而在 320 pt 右侧栏下，扣除 [`LibraryDetailView.swift`](../Sources/SpinLabApp/Features/Library/LibraryDetailView.swift) 外层 `.padding(.horizontal, 16)`（32 pt）与 ScrollView 内层 `.padding(.horizontal, 12)`（24 pt）后，内部可用宽度仅剩 **264 pt**（`320 - 32 - 24`），必然被裁切。
  3. **Result Definitions Manager**（[`ResultDefinitionManagerView.swift`](../Sources/SpinLabApp/Features/Library/ResultDefinitionManagerView.swift)）：内嵌在 [`LibraryManagementDetailView.swift`](../Sources/SpinLabApp/Features/Library/LibraryManagementDetailView.swift) 的 `LibraryOverviewView` 中，**同样挂载在右侧 Detail 栏**（320–720 pt，且外层有 `.padding(.horizontal, 28)`），其 `createForm` 与 `editRow` 将 3 个输入框和按钮放在单行 `HStack`，在 320–420 pt 下同样局促，需按同一容器的真实可用宽度做紧凑分行。

### 2.2 产品界面职责：Results 保留在右侧 Inspector
- 在 Sample Workspace 路由下，中间 Primary 栏（[`LibrarySampleWorkspacePrimaryView.swift`](../Sources/SpinLabApp/Features/Library/LibrarySampleWorkspacePrimaryView.swift)）专注于 **Batch 内样品切换 + Sample Plots 总览**；右侧 Detail（Inspector）栏承载 **Sample 档案（Tags、Results、Measurement Data、Measurements Done、Metadata）**。
- **决策**：Sample Results 的查看与当前值录入继续保留在右侧 Inspector 栏，不为了抽象的“主操作放中间”而拆分样品档案或挤压 Plots 空间；通过将每个 Result 条目改为紧凑的两行布局解决 320 pt（内部 264 pt）宽度下的裁切问题。

### 2.3 修正 `04_UI_RULES.md` 中与现实脱节的绝对化条款（含 VC-1 / VC-3 作用域收敛）
Audit 发现 `04_UI_RULES.md` 现有多处 `[HARD][must]` 与其自身推荐的共享组件 [`MetadataViews.swift`](../Sources/SpinLabApp/UI/MetadataViews.swift) 及全仓实践自相矛盾，需在 Step 1 一并理顺，消除规范内部冲突：
1. **放宽 `.secondary` 文本颜色限制**：原规则一律禁止可读文字使用 `.secondary`。修订为：正文、核心数值、主标签保持 `.primary`；**字段名标签（如 `MetadataValueRow` 的 label）、辅助说明、时间戳/计数等次要信息允许使用系统 `.secondary`**（前提是在 macOS 标准背景下保持清晰可读，不用低对比度浅灰隐藏关键信息）。
2. **放宽 `.monospaced()` 字体限制**：原规则一律禁止对路径、Sample UID 使用 `.monospaced()`。修订为：一般界面文案与科学参数名称使用统一系统字体；**机器标识符（如 `smp_...` UID）、文件系统路径、版本号、哈希/规则指纹与等宽数值对齐场景允许使用 `.monospaced()`**。
3. **收敛 Control Visual Contract（`VC-1`、`VC-3` 等）的严格控制要求至实际需要区域**：目前 `04_UI_RULES.md` 的 `Control Visual Contract` 将 `VC-1`（所有控件文字严禁使用 `.secondary`）与 `VC-3`（控件文字样式只能取自 `WorkbenchUIStyle`，严禁 `.secondary`）写成了覆盖全 App 所有交互控件组的硬规则。若只修改前两条而不改动 `VC-1` / `VC-3`，`04` 内部仍会自相矛盾，且违背“不把 Workbench 重型合同推广到 Library”的决定。因此 Step 1 应将 `WorkbenchUIStyle` 强制入口及 `VC-1…VC-11` 中专属于 Workbench 密集控制面板的严格约束，明确限定在 **Workbench Controls Surface（或显式接入该套件的控制区）**，全局层面仅保留核心可读性、最小可操作尺寸与不裁切原则。

### 2.4 语言边界与轻量 CJK Guard 的真实定位
- **按来源区分语言**：
  - **固定 UI 文案**（按钮、标题、placeholder、状态/错误提示、确认弹窗）：遵循 `04_UI_RULES.md` 全英文规定。
  - **科研领域键名与用户输入**（样品名、备注、用户自定义 Result Definition 名称/限定词、Registry/搜索映射中的 `"厚度"` / `"氧压"` / `"温度"` / `"能量"` / `"生长温度"` / `"衬底"` / `#测试温度` 等）：保留原始语言与语义，不当作 UI 违规翻译。
- **轻量 CJK Guard 的能力与局限**：
  - 在 `scripts/ui_rules_check.py` 中增加针对 UI 源码（`Sources/SpinLabApp/Features` 及直接向 UI 提供 `LocalizedError` 文案的服务文件如 `LibraryResultService.swift`）的 CJK 字符串计数检查，并纳入 `scripts/ui_rules_baseline.json`（只减不增）。
  - **明确预期**：基于按文件计数的 baseline 棘轮只能防止“新建 UI 文件写中文”和“既有文件中文数量增加”，无法 100% 拦截同一文件内“删一句旧中文、换一句新中文”的等量替换；不为此开发复杂的 Swift 语义分析器，剩余边界由常规 Review 把关。

---

## 3. 收敛后的两步落地路线（取代原 T1–T4 四阶段）

不再单开纯文档审计阶段或独立工具建设阶段，压缩为 **Step 1（集中落地）+ Step 2（日常演进）**：

### Step 1 — 最小规则修订 + Sample Detail / Result Definitions 直接修复（单个独立实施 PR）

1. **修订 `specs/04_UI_RULES.md`**：
   - 在顶部加入 §1 的核心设计哲学；
   - 修正 `.secondary` 与 `.monospaced()` 规则，使其与 `MetadataViews` 及 macOS 原生习惯一致；同时将 `VC-1`、`VC-3` 等要求所有控件文字只能使用 `.primary` 且必须从 `WorkbenchUIStyle` 取值的严格条款限定在 Workbench Controls Surface（或显式接入该套件的控制区），消除 `04` 内部矛盾；
   - 明确右侧 Detail（Inspector）栏在 `rightMin = 320 pt`（Sample Detail 内部可用宽度 **264 pt**）下的布局底线：禁止单行子控件 `minWidth` 总和超过容器可用宽度导致裁切；宽度不足时采用两行布局或 `FlowLayout` 换行。
2. **修复右侧栏布局裁切**：
   - `LibrarySampleDetailHeaderView`：标题与操作按钮支持窄栏换行或紧凑分组，确保 320 pt（内部 264 pt）下所有按钮完整可见可点。
   - `SampleResultsSection`：由单行 5 元素 `HStack` 改为两行紧凑布局（第一行显示 Definition Label 与当前值；第二行放置数值输入框、`Confirm` 与 `Clear`），移除会导致超出 **264 pt** 内部宽度的硬编码 `minWidth` 组合。
   - `ResultDefinitionManagerView`：适配 `LibraryOverviewView` 所在的同一右侧栏宽度（320–420 pt），将新建/编辑的 3 个输入框（Name / Unit / Qualifier）与操作按钮改为在窄栏下不挤压的两行或自适应排布。
3. **统一本次触及模块的固定 UI 英文文案**：
   - 将 `LibrarySampleDetailHeaderView`、`LibraryDetailView`（`修改日志` 按钮）、`SampleResultsSection`、`ResultDefinitionManagerView`、`LibraryResultService`、`SpinLabAppState+Results` 中的固定中文 UI 文案与错误提示统一为英文。
4. **接入轻量 CJK Guard**：
   - 在 `scripts/ui_rules_check.py` 中增加 CJK 字面量棘轮规则，更新 `scripts/ui_rules_baseline.json`，保留既有文件存量与领域标签基线，确保新增 UI 代码默认遵循英文文案规范。
5. **本机真实窗口验证**：
   - 编译桌面 App（`./scripts/build_desktop_app.sh debug`），在两类宽度下实测：
     - 正常三栏下右侧 Inspector 处于 **320 pt（最小，内部 264 pt） / 420 pt（理想）** 时，Sample Detail 与 Library Overview（Result Definitions）在只读、编辑、空状态、长 Label 状态下均无裁切、按钮可达；
     - 窗口总宽 **< 938 pt**（`180 + 420 + 320 + 2×9`）时，确认三栏退化行为与滚动可用性（必要时评估主窗口 `minWidth` 约束）。

### Step 2 — 日常演进与顺手清理（不单独立项）

- 后续任务修改其他历史视图（如 `MeasurementConditionDetailView`、`RecomputePreviewPanel` 等）时，顺手清理该文件的旧中文 UI 文案与 `numeric-spacing` / `small-text` 基线，并用 `./scripts/check_ui_rules.sh --update-baseline` 收紧。
- 当布局逻辑重复、维护成本明显增加，并且共享实现能够有效降低重复缺陷时，才考虑提取共享组件（不设死板的“重复 N 次”硬阈值）；仅当某类缺陷反复复发且可低成本确定性检测时，才新增自动检查。

---

## 4. 已拍板的决策汇总

| 议题 | 决定 |
|---|---|
| 实施阶段划分 | **四阶段压缩为两步**（Step 1 一次落地规则修订+核心页面修复+轻量 Guard；Step 2 日常顺手清理） |
| Sample Results 位置 | **保留在右侧 Inspector（Detail 栏）**，改为两行紧凑布局解决 320 pt（内部 264 pt）裁切 |
| Result Definitions Manager | 同样位于右侧 Detail 栏（Library Overview 内），在 Step 1 一并按 320–420 pt 容器宽度做紧凑布局与英文文案统一 |
| UI 视觉基线 | **原生 macOS 轻量基线**；放宽 `04` 中对 `.secondary` 与 `.monospaced()` 的一刀切禁令，并将 `VC-1`/`VC-3` 的 `WorkbenchUIStyle` 严格限制收敛到 Workbench 控件区 |
| 是否引入新 UI 框架/DSL | **不引入**；普通页面直接用原生 SwiftUI + 现有轻量 token；共享组件按“降低重复缺陷 vs 维护成本”提取，不设硬性次数阈值 |
| 是否增加 CJK Guard | **增加轻量按文件计数棘轮**（覆盖 `Features/` 与 `LibraryResultService.swift`），防增量回归，不搞重型 AST 分析 |
| 是否增加截图 CI | **不增加**；Step 1 采用本机桌面构建与真实窄窗状态（320 pt Inspector / < 938 pt 窗口）实测 |
| 是否保留顶层设计哲学 | **保留**，在 Step 1 直接写入 `specs/04_UI_RULES.md` 开头 |

---

## 5. 本 PR 的范围（设计收敛 + Step 1 落地）

- **规范回写**：已将顶层设计哲学、`.secondary`/`.monospaced()` 放宽、`VC-1`/`VC-3` 作用域收敛及右侧栏 320 pt（内部 264 pt）窄窗底线写入 `specs/04_UI_RULES.md`。
- **Step 1 代码与 Guard 落地**：
  - 修复 `LibrarySampleDetailHeaderView`、`SampleResultsSection`、`ResultDefinitionManagerView` 在右侧栏的窄窗两行/换行布局；
  - 将上述组件及 `LibraryDetailView`、`LibrarySheets`、`LibraryResultService`、`SpinLabAppState+Results`、`SaveLibrarySampleEditsUseCase` 中的固定中文 UI 文案统一为英文；
  - 在 `scripts/ui_rules_check.py` 与 `scripts/test_ui_rules.sh` 接入 `cjk-ui-literal` 棘轮并更新 `scripts/ui_rules_baseline.json`（同时将 `LibrarySampleDetailHeaderView.swift` 的历史 `numeric-spacing` / `small-text` 清零）；
  - 版本号更新至 `v6.3.1`。
