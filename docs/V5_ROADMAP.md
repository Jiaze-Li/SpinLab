# SpinLab 5.x Roadmap

> 版本号是分类标签，不是时间线。版本段之间可交叉推进。
> 每个版本段是收集箱——发现问题按分类归入，做的时候再排优先级。
> 具体迭代只在每个路线内部推进。

## 版本段索引

| 段 | 主题 | 状态 |
|---|---|---|
| 5.0.x | 设计和规划 | 进行中 |
| 5.1.x | 跨区域技术债 + 基础设施 | 收集中 |
| 5.2.x | Import 管线 + Inbox 逻辑/架构 | 收集中 |
| 5.3.x | Workbench 逻辑/架构 | 收集中 |
| 5.4.x | Library 逻辑/架构 | 收集中 |
| 5.5.x | 全区域 UI 统一优化 | 收集中 |
| 5.6.x | 预留 | — |
| 5.7.x | Docs 专项 | 进行中 |

---

## 5.0.x — 设计和规划

### 5.0.0
- [x] 建立知识积累系统（philosophy / features / known_issues / devlog）
- [x] 建立版本路线图

---

## 5.1.x — 跨区域技术债 + 基础设施

### 5.1.0 — Assessment + 低风险速清
- [x] AppState 分解 scope assessment：清点 Library 域属性/方法、依赖图、迁移边界和顺序
- [x] try? audit 剩余项：LibraryStore createDirectory 和 read paths `[来源: TECH_DEBT_EXECUTION_LOG Round E]`
- [x] 旧 CodingKeys 发布周期确认：PendingImportConfirmationDraft + RoutePlan.status decode path
- [x] 同步更新 TECH_DEBT_EXECUTION_LOG

### 5.1.1 — AppState 分解（主体）
- [x] LibraryFacade + LibraryCommandCoordinator 折叠进 LibraryFeatureStore
- [x] 13 个 AppState 转发方法删除，调用方迁移到 appState.library.xxx()
- [x] 选择代理属性迁移：4 个属性移入 LibraryFeatureStore，didSet 回调持久化
- [x] 验收：CLAUDE.md temporary exceptions 的 Library 条目已缩减，无 Library 域透传残留

### 5.1.2 — 废弃代码清理 + 错误处理
- [x] 旧 CodingKeys 迁移码清理（已在 5.1.0 完成：PendingImportConfirmationDraft + RoutePlan.status）
- [x] 错误处理体系统一审查：无新 violation，LibraryStore/XLSXSyncService 已有日志+fail-soft 模式，关键写入路径使用原子事务

### 5.1.3 — 测试基础设施
- [x] 覆盖率基线建立：506 tests, 1.98% line coverage (4.17% logic-only). Workbench render pipeline well-covered; App/State layer at 0%.
- [x] 关键路径测试补全（优先补分解后的 FeatureStore facade 方法，需 fixture 基础设施）

### 5.1.4 — Workflow alias 数据驱动 + FeatureStore 测试补全
- [x] Workflow ID alias 硬编码清理：SearchWorkflowMeasurementsUseCase if-else 链改为枚举 aliases computed property，统一 canonical 逻辑 `[来源: TECH_DEBT_BACKLOG]`
- [x] RegistryFeatureStore 关键路径测试：初始化、applyPresentation、状态清除（3 cases）
- [x] InboxFeatureStore 关键路径测试：初始化/选择、导入分发、apply 移除、workspace 裁剪、选择自动调整（15 cases）
- [x] 文档状态同步：TECH_DEBT_BACKLOG 完成度与 roadmap 对齐

### 5.1.5 — 规则管理统一 + 自动同步基础设施 [~]

**状态**：`[~]` 进行中。s1–s10 已完成；2026-04-27 追加 s11（三个匹配本子 UI + 字段命名统一 + Store 流程骨架抽 + Shell 容器抽），s11-design 实施方案已收敛（[handoff](../handoff/2026-04-27-s11-design.md)），s11-exec 待执行。

**动机**：4·25 事故暴露规则架构散落多文件、bundle 与 runtime schema 不一致、半成品迁移路径并存（如代码层齐全但永远不会真存在的 `conditions_rules.json` 分文件）。同一份概念多处存放、隐式"分文件赢"约定、bundle 与 runtime 没有自动同步——任何一处改动都可能让另一处静默漂移。需要从根上修。

**顶层原则**（已上升为 App 顶层规则，待写入 `docs/philosophy.md`）：
> "你看见的，就是 App 设置的。" 所有规则——包括平时几乎不改的——都必须在 UI 里看得见、改得动。

---

#### 二次规划（2026-04-26，s3–s6 重做）

s2 完成后回顾发现：原 6 类清单（按 schema 文件机械切分）与产品语义不符 —— 同一概念跨多文件、不同概念混入同一文件，UI 上按"文件"展示无法对应用户心智模型。重新按**产品流程**切分，由 Jack + Claude 对抗讨论 + Codex 独立 review（adopt-with-fixes）收敛得到下面这套方案。

##### 拍板要点

**A. 后台架构升级为 5 类规则文件（非 6 / 非 7）**

按 inbox 数据流顺序排列，每类一文件，仓库 `Sources/SpinLabApp/config/` 与 runtime `~/Library/Application Support/SpinLab/config/` 各放一份字节级一致。

| # | 本子（面板侧栏顺序） | 内容（来源 → 新本子映射） |
|---|---|---|
| 1 | **Import Filters** | 哪些文件后缀算数据。来源：`library_import_rules.json` 的 `import.supportedFileExtensions` + `import.ignoredFileExtensions` |
| 2 | **Filename Tokenization** | 文件名怎么切片标记。来源：`filename_parse_rules.json` 的 `tokenization` + `sources` + `channel.aliases` |
| 3 | **Sample Identification** | 从文件名识别 sample 的全套规则。来源：`sample_id_rules.json` 全部 + `substrate_normalization_rules.json` 全部（衬底材料 / 处理 / 晶向 / 别名 / 显示名都同段，每行衬底材料后带"显示成 X"字段） |
| 4 | **Workflow** | 每个 workflow 一行同时展示：ID（机器读，固定不改）+ title（用户看，可改）+ 怎么从文件名识别 + 需要哪些 condition + 触发哪些子标签。来源：`workflow_registry.json`（去 `parentID`）+ `workflow_match_rules.json` + `filename_parse_rules.json.measurementNameRules` + `measurement_tag_rules.json`（**子标签数据模型保持全局清单**，不分片到 workflow 内） |
| 5 | **Measuring Condition** | condition 数值识别规则。来源：`filename_parse_rules.json` 的 `conditions.*` + `conditionDefinitions` + `batch` 段 |

**B. 退役项**（一次性清理）

- `workflow_id_policy.json` 整文件 + `Workflow/WorkflowIDAllocator.swift`（含 `WorkflowIDPolicy` / `DefaultWorkflowIDAllocator` / `WorkflowIDPolicyLoader`）整文件 —— 未来新增 workflow 时 UI 提供"输入 ID"框，用户手动一次性给定，机器侧不再自动分配。复制现有 workflow 后微调是新增 workflow 的标准方式
- `WorkflowDefinition.parentID` 字段 + 现有 XY workflow 的 `parentID="Rotation"`（**带向后兼容解码**：旧数据含该字段仍可解码不崩，新写出文件不含；防 Jack 已有 runtime 数据首启炸）
- `filename_parse_rules.json.rotationHintRules`（90shift → "+90deg for I parallel B" 那条文案）—— 归显示层硬编码，不再作为可编辑规则。Codex review 裁决理由：当前只一条稳定映射，本质是注释文案不是业务策略，留在 schema 会污染"解析规则"与"显示文案"边界

**C. 推迟到 Library 专项做的项**（**过渡期受控例外**，必须在 Library 专项时一并退役 fallback）

`library_import_rules.json` 的 `registry` 段全部不进本期 5 本子面板，包括：`sampleHeaderAliases` / `batchHeaderAliases` / `substrateHeaderAliases` / `excludedSheetNames` / `sampleCellSeparators` / `numericKeyAliases` / `substrateMaterialTokens` / `substrateProcessingKeywords` / `metadataLookupAliases`。这些消费方都在 Library / Registry 解析路径，与 inbox 测试文件读取无关。

衬底材料清单当前在 `substrate_normalization_rules.json` 与 `library_import_rules.json` 各有一份字面相同的副本，本期保留两份不合并；Library 专项时合并。

`Extensions/ExtensionPoints.swift` 的 `RegistryMetadataAliasBook.fallbackAliases` 是代码内默认值（用户 UI 暂不可见），是顶层原则"看见即唯一规则"的**已知例外**。Library 专项验收必须包含"删除 fallback + 别名表上面板"。

**D. UI 架构（与原方案保持）**

单一"规则管理"面板，5 个分区对应上述 5 本子。入口在 Inbox 中间列「Inbox Operations」标题旁的文字按钮（不做全局菜单入口）。s2 已搭的左侧分区列表 + 右侧详情面板的窗口框架沿用，6 分区结构改为 5 分区。

s2 已实现的 4 类编辑 UI 代码（`FilenameParseRulesSection` / `SampleIDRulesSection` / `WorkflowMatchRulesSection` / `SubstrateRulesSection`）作废重做 —— 但 UI 模式（主从布局 / 列表内嵌 / 保存校验 / 外部冲突 / hash precondition / atomic 写）的套路 s5 重写时直接复用，不是从零开始。

**E. 自动同步机制（与原方案保持）**

UI 一按保存 → 写本地 → 自动写仓库镜像。反向同步用内容指纹（哈希），不用 mtime。原子写 + 单份回退副本（覆盖前一份，不累积时间戳历史）。仓库目录指针机制：runtime 侧一个指针文件，找不到 / 为空就跳过镜像写入不报错。

**F. 迁移策略（与原方案保持）**

一次性迁完不留中间状态。新 schema 由本期重新拍板，不背旧格式包袱。迁移代码只负责读旧 → 按新结构转写一次落盘，旧 schema 用完即抛，不保留兼容路径或并行加载逻辑。迁移前自动创建 `.backup-<ts>` 副本，迁移成功才删原文件。旧文件 decoder 仅在首启迁移时用，迁移完成后从代码删除。

**G. 关键 acceptance gate（s5 实施时必满足）**

R1 —— 工作流 ID 策略相关规则保存后立刻生效，App 内不存在"已加载副本 vs 磁盘"两个版本（不接受"保存了但要重启 App 才生效"）。s5 起手前必须排查所有持有该策略的活跃组件路径，决定刷新机制（重读 / 注入新策略 / invalidate cache）。

##### 否决方案及理由（不要后续 agent 推翻）

- ❌ 把 5 本子拆回 6 / 7 本子 —— Workflow Matching + Workflow Condition 合并成一本 Workflow，让"匹配规则 + condition 需求 + 子标签"在每个 workflow 一行内同时摊开操作连贯
- ❌ 恢复父 workflow 概念 —— Jack 原话："未来就一个一个维护，如果有相似的就直接 copy 工作流程然后微调"
- ❌ 保留 workflow_id_policy 自动分配 —— Jack 原话："这个要求一次确定之后未来不改了，不要变动不然机器会误解，title 可以反复改给用户看的"
- ❌ Library 侧规则（registry 段）放进本期 5 本子 —— Jack 拍板分两期，本期 inbox 侧，Library 专项一次性做完 + 合并衬底重叠 + 退役 fallback
- ❌ rotationHintRules 留作可编辑规则 —— Codex review 裁决归显示层硬编码
- ❌ 子标签 schema 改成每 workflow 自带清单 —— UI 上挂在 workflow 下展示是组织方式；数据模型保持全局表，避免 5.1.5 内做 schema 大重构
- ❌ 手动同步按钮 —— Jack 原话："我不想我按一下同步，我要自动同步"
- ❌ 把不常改的规则排除在 UI 外 —— 违反"看见即设置"原则
- ❌ 多入口并存或快捷跳转 —— 后台一处管理 → UI 也一处
- ❌ 在现有 UI 上改良叠新机制 —— Jack 原话："现在有的清理掉，全部重新做，不要在烂地里改良"
- ❌ 入口放全局菜单 —— 明确放 Inbox
- ❌ 用 mtime 判反向同步 —— git 不保留 mtime 会误判
- ❌ 分两阶段迁移（主文件 schema 升级 + 分文件合并各自一次）—— 避免半成品中间态
- ❌ 任务编号继续 4 会话 —— 重新规划为 s3 / s4 / s5 / s6 共 4 会话，主题与原规划完全不同

##### 任务拆分（s3–s6，**2026-04-26 重新规划**）

| 会话 | 主题 | 工作量 |
|---|---|---|
| s1 ✅ 已归档 | schema 落地 + 旧 UI 删除 | — |
| s2 ✅ 已归档 | 统一面板骨架 + 4 类已有规则编辑 | — |
| s3 ✅ 已归档 | 盘点 + 5 本子分类设计稿 + 退役调用点全清单 + 新 schema 草案 | — |
| s4 ✅ 已归档 | 5本子schema落地 + RuleLoader/RulesMigration重写 + WorkflowIDAllocator/parentID/rotationHintRules退役 + 旧bundle文件删除 + V210 fixture更新；swift build clean + 测试全绿。[实施摘要](../history/v515_s4_schema_migration.md) | — |
| s5 ✅ 已归档 | 5 个 section UI 重写 + close-alert / save / discard / 外部冲突集成 + R1 acceptance gate（保存立即生效）路径 + 测试补全（36 tests）；swift build clean；commit ea09161。[实施摘要](../history/v515_s5_rules_panel_rewrite.md) | — |
| s6 ✅ 已归档 | 自动同步引擎：RepositoryPointer（含 .git 身份校验）+ RulesSyncEngine（dual-write + reverseSyncOnStartup）+ degraded banner + mirror 警告图标 + 32 tests（20 engine + 12 startup）；swift build clean；68/68 V515 tests green；commits 99514e2 + 4a586fe。[实施摘要](../history/v515_s6_auto_sync_engine.md) | — |
| s7 ✅ 已归档 | 任务 2/3/4 落地：WorkflowDefinitionStore（读 config/workflow.json）+ WorkflowRegistryRetirementService（外层 registry 合并）+ parentID 兼容码删除 + RulesBootstrapper 替换 RulesMigration + WorkflowRegistryView 只读重写；5 commit（08c7f8a–f7939c4）+ 11 tests（79/79 V515 green）。[实施摘要](../history/v515_s7_rules_tail_cleanup.md) | — |
| s8 ✅ 已归档 | 设计稿 + handoff：condition definitions inline + substrate row-oriented + MatchSpec.matchValues 命名统一；双盲对抗收敛，handoff 写 archive/2026-04-26-5.1.5-s8-schema-second-pass.md | — |
| s9 ✅ 已归档 | 按 s8 handoff 执行：ConditionDefinition inline + SubstrateConfig row-oriented + MatchSpec.matchValues 全仓统一 + RulesBootstrapper v1→v2 迁移（atomic + state + backup + 幂等）；7 commits；84/84 V515 green + 27/27 V210 green。[实施摘要](../history/v515_s9_schema_second_pass.md) | — |
| s10 [x] 已归档 | v4 substrate schema 全量落地：SubstrateEntry 统一三表 + batchPrefixes + UI 重写 + v3→v4 bootstrapper 迁移；117 V515 + 18 V221 全绿。[设计思路](../history/v515_s10_substrate_redesign.md) | 02abdfe + 2523f20 |
| s11 [~] 方案完成 | 三个匹配本子（Sample Identification / Workflow / Measuring Condition）UI + 字段命名 + Store 流程骨架抽 + Shell 容器抽：条目头 id、展开 displayName、scope 全删（含求值算法零改动 + 解码层最小兼容性扩展）、label→displayName 闭环（含 ConditionFieldCatalog 链路）；分 exec.A（schema decode compat + migration）+ exec.B（strategy + shell + 统一编辑器 + alias 清理）两段独立 commit | [handoff/2026-04-27-s11-design.md](../handoff/2026-04-27-s11-design.md) |

总计约 **44–66 h** 跨 7 对话（s1–s9，s8 是设计对话不计工作量）。s5 / s9 是工作量最大的执行会话。s10 追加，2 commits 落地。

##### s7 / s8 / s9 任务清单（s3 收敛后识别，本期必做）

s3 双盲对抗 Round 2 决策（详见 handoff `2026-04-26-5.1.5-s3-rules-redesign.md`）为保 s4 风险最小，把以下 6 项明确推后。这些**仍属 5.1.5 任务范围**，按"是否涉及数据迁移"分两批：

**s7（设计+执行同会话，纯删除/合并，无数据迁移）**

| # | 任务 | code pointer | 估时 | 来源 |
|---|---|---|---|---|
| s7-2 | workflow.json 与 workflow_registry.json 合并为单一权威文件（含完整调用图闭包扫描 + 回滚脚本 + 幂等重跑硬门禁）| `config/workflow.json` + `~/Library/Application Support/SpinLab/workflow_registry.json` + `Workflow/WorkflowRegistryStore.swift` | Medium-High | s3 D3 |
| s7-3 | parentID decode 兼容彻底删除（CodingKeys + init(from:) 显式吞行 → 0）| `Workflow/WorkflowDefinition.swift` | Low | s3 D4 三段式第 3 段 |
| s7-4 | RulesMigration 模块内旧 7 文件 decoder 删除 | `Import/Rules/RulesMigration.swift` (assembleNewSchema 旧文件读取段) | Low | s3 D8 |

**s8 设计 / s9 执行（涉及数据迁移 + 全表 touch，单独对抗）**

| # | 任务 | code pointer | 估时 | 来源 |
|---|---|---|---|---|
| s9-1 | Condition definitions schema — 删 binding + 每条 inline 自己的 unitPattern / tokenMapRules + 退役 RuleCanonicalizer.normalizeConditionDefinitionBindings | `config/measuring_condition.json` + `Import/Rules/RuleCanonicalizer.swift` + 消费侧 | Medium | s3 D2 |
| s9-5 | Substrate 数据层 row-oriented 重组 — `materials[]` + `treatments[]` 数组 | `config/sample_identification.json` + 消费侧 substrate 解析链 + 迁移代码 | Medium | s3 D12 |
| s9-6 | 字段命名一致性整理（rename / 拍平按统一规则推一遍）| 5 本子 schema 全部 | Low-Medium | s3 D1 |

##### s11 任务清单（2026-04-27 追加，三个匹配本子 UI + 字段命名统一）

**动机**：5 个规则本子虽然管理层已坐到同一面板下（s5 已完成 RulesPanelView + RulesManagementStore 统一），但展开后每个 section 各长一套表单：条目头有的用 id 有的不用、字段叫 label 还是 display name 不统一、Workflow 里的 measurement tag rules 多出一个 scope 字段（Sample Identification 已删）、匹配规则编辑器 UI 在三本之间样式不一致。Jack 在 2026-04-27 反馈："matching 最好走同一个逻辑不要每个本子自己一套，独有的功能不如 regex 可以再加，但是 matching 能做一套就做一套，还有显示逻辑，可以把 id 作为条目的 head"。

**范围**（仅三个匹配本子 + Workflow 内的 measurement tag rules 区块）：

- Sample Identification
- Workflow（含 measurement tag rules 子区块）
- Measuring Condition

不动 Import Filters 和 Filename Tokenization —— 它们不是"按规则识别文件"的匹配本（一个决定哪些文件进来，一个决定文件名怎么切词），是匹配的上游。

**拍板要点**：

1. **条目头统一 = id**。三个本子展开列表里，每行折叠状态显示 id，展开后第一行才是 display name。Measuring Condition 当前用 label 作为头需要改成 id。
2. **字段命名收敛为 display name**。Measuring Condition 的 label 字段重命名为 displayName（schema 同步迁移，含向后解码兼容首启）；Workflow 与 Sample Identification 已是 displayName，保持。
3. **scope 字段全删**。Workflow 的 measurement tag rules 当前还有 scope（tokens / joined），Sample Identification 已经在 s10 删掉。本期把 Workflow 这边也删掉，匹配统一走 token-scoped（与 s10 substrate 行为一致）。
4. **匹配规则编辑器 UI 统一**。三个本子展开后的"match 区"用同一个 SwiftUI 组件渲染（不是新写一个共享组件，是把现有 MatchRuleEditor 推全），每条规则形态一致：type（equals / contains / regex / 等）+ 值。各本子独有的字段（Workflow 的 conditionFieldIDs、Measuring Condition 的 unitPattern / tokenMapRules / kind）作为额外区块挂在共享匹配区**之外**，不混进匹配区。
5. **匹配引擎不动**。三个本子底层求值已是同一套（FilenameRuleSet 的 MapRule / CompiledMapRule + stringMatches/tokenMatches），本期只动展示与字段命名层，引擎零改动。
6. **regex 等独有匹配能力保留**。Measuring Condition 有 regex pattern，是真正"独有的功能"，作为 type 选项的一种保留在共享编辑器里（不是单独 UI）。

**任务拆分**：

| 会话 | 主题 | 工作量 |
|---|---|---|
| s11-design | 设计稿对抗：三本子当前 UI 形态盘点 + 共享匹配编辑器接口 + label→displayName 迁移路径 + scope 删除影响面 → handoff | 设计会话 |
| s11-exec | 执行：Measuring Condition schema 迁移 (label→displayName) + Workflow measurement tag rules 删 scope + 三本 UI 推全共享编辑器 + 列表头改 id；测试同步更新 | 中（10–14 h） |

**关键 acceptance gate**（s11-exec 验收时必满足）：

- **AG1** 三个本子的列表头都显示 id；展开后第一行是 display name，第二行起是匹配区。
- **AG2** Measuring Condition 持久化字段统一为 displayName；含旧 label 字段的 runtime 文件能解码并迁出（atomic + backup）。
- **AG3** Workflow 的 measurement tag rules 不再有 scope 字段；旧 scope 字段在解码时静默丢弃，新写出文件不含。
- **AG4** 三本的匹配规则区块视觉与交互一致（同一个组件实例化），独有字段（conditionFieldIDs / unitPattern / tokenMapRules / kind）位于匹配区之外。
- **AG5** Measuring Condition 的 regex pattern 作为 type 下拉选项之一存在，不是独立 UI。
- **AG6** 匹配引擎零改动 —— 求值结果与 s10 完全一致，回归测试全绿。

**否决方案及理由**（不要后续 agent 推翻）：

- ❌ 五本子全统一 UI —— Import Filters / Filename Tokenization 不是匹配本，强行套同一个壳会让上游规则被错误归类
- ❌ 把 Workflow 的 measurement tag rules 抽到独立第六本子 —— 它的"匹中→贴标签"语义就是为某个 workflow 服务的，独立出来反而失去上下文
- ❌ 把匹配引擎再抽象一层（输入→规则→产物的更上层框架） —— 引擎已统一，再抽是为不存在的需求加层
- ❌ label / displayName 双名并存兼容 —— 当前全仓只有 Measuring Condition 一处用 label，一次性迁完不留双名
- ❌ scope 保留作为可选字段 —— Sample Identification 已在 s10 删掉证明用不上；保留只会让"看见即设置"原则破例
- ❌ 为每个本子各自定制匹配编辑器 —— 用户原话明确"matching 能做一套就做一套"

**来源**：2026-04-27 与 Jack 对齐。从"5 个本子各自 UI 不一致"展开为"三个匹配本统一 UI + 字段命名 + 引擎共用确认"专项。

##### s3 设计稿必须包含的盘点清单（让 s4 不漏点）

s3 输出的设计稿必须显式列出以下代码点，s4 才能一次清干净。Codex review 已查证以下消费侧：

- 规则加载 / 路径：`Sources/SpinLabApp/Import/Rules/RulesConfigPaths.swift`（含 `workflowIDPolicyURL` + `allSchemaFileURLs`）/ `Sources/SpinLabApp/Import/Rules/RuleLoader.swift`（7 文件装配 + composite hash）/ `Sources/SpinLabApp/Import/Rules/RulesMigration.swift`（`oldFilenames` / `targetFiles` / `defaultWorkflowIDPolicyData`）
- 规则数据结构：`Sources/SpinLabApp/Import/Rules/FilenameRuleSet.swift`
- 规则面板与 store：`Sources/SpinLabApp/Features/RulesPanel/RulesPanelSection.swift`（含 `.workflowIDPolicy` case）/ `RulesPanelView.swift`（含 `WorkflowIDPolicySection` 渲染）/ `RulesManagementStore.swift`（含 `WorkflowIDPolicySummary` 读取逻辑）/ `Sections/FilenameParseRulesSection.swift` / `Sections/WorkflowIDPolicySection.swift`
- workflow 注册：`Sources/SpinLabApp/Workflow/WorkflowDefinition.swift`（`parentID` 字段 + Codable keys + decode 路径）/ `WorkflowRegistryStore.swift`（seeded defaults `parentID: nil` + `normalizeOptional(definition.parentID)`）/ `WorkflowIDAllocator.swift`（整文件退役）
- Library 延期项消费侧（**防误删**，本期不动）：`Sources/SpinLabApp/Library/LibraryRegistryParser.swift` / `Sources/SpinLabApp/Registry/RegistryLookupRuleBook.swift` / `Sources/SpinLabApp/Registry/RegistrySheetFilter.swift` / `Sources/SpinLabApp/Extensions/ExtensionPoints.swift`

##### s4 启动验证最小集（收尾门禁）

- 规则加载：runtime 无旧 7 文件时能正常加载新 5 schema
- 规则窗口：仅出现新 5 本子，无旧 section 残留
- 历史 runtime：含 `parentID` 的旧 registry 能迁移并新写出无该字段
- import 解析：sample / workflow / conditions 仍可产出草稿

### 5.1.6 — Codex 派发提速基建（设计方案）

**状态**：`[~]` 已规划设计，未启动执行。具体执行细节（每个杠杆的范围与 schema）handoff 时再拍板。可与 5.1.5 并行或在其完结后启动。

**动机**：双 AI 对抗机制下 SpinLab 的 Codex 派发耗时明显高于轻量项目（如纯 Python + mixin 架构）。归因（Codex 独立查证后裁决，2026-04-25）：

1. **分层架构成本**：CLAUDE.md 强制 Domain → UseCase/Service → Store → View 五层 + UI/logic 必须拆 commit。一个改动 brief 必须 inline 多层上下文才能让 Codex 准确执行
2. **项目体量**：Sources/SpinLabApp 共 194 个 Swift 文件、约 3.68 万行，中位数 101 行/文件，p90 441 行，最大约 1800 行（应用主状态协调器）。约 6 个 1000+ 行重文件全部位于 store/state 层
3. **派发协议放大效应**：dispatch.md 的 30-turn 工具调用硬顶在大文件项目里被放大 —— 同样 30 次调用预算，长文件项目单位 turn 信息密度低；同等 brief 准备投入下，体感"Codex 在 SpinLab 更慢"，本质是单位 turn 信息密度下降，不是 Codex 变慢

误判矫正：曾有"SpinLab 慢是因为缺 core modules 清单 / 文档分层不成熟"的归因，与仓库事实冲突 —— SpinLab 现有 13 份 specs（约 1564 行）+ 36 份 docs（约 1189 行）+ 高密度 CLAUDE.md，文档框架不缺。真正瓶颈是上述三条。

**候选杠杆**（按推荐优先级排，最终采纳由 handoff 阶段决定）：

#### 杠杆 A — 变更类型 → 最小必读清单速查表（推荐先做）

- 形式：每类常见任务（Workbench 搜索、Library 编辑、Inbox routing、规则管理等）对应最小必读文件清单 + 每文件锚点行段 + 可省略层条件
- 作用：把"先找哪里读"从运行时摸索变成静态索引，直接减 turn，不牺牲准确率
- 投入：1–2 小时建库（3–5 类常见任务起步）
- 单次派发预计节省 2–5 min（导航 + 试探性 grep）
- 整体派发耗时压到原来 85–95%
- 风险：接近零，最坏白做
- **关键注意点（必须配套做）**：A 真正的风险不在做错，**在做完忘了用**。如果速查表写完，下次派发 brief 准备还是凭手感找文件，那就白做。要让它真生效，必须在 `~/.claude/docs/dispatch.md` §0 派发前必读 或 `CLAUDE.md` 项目规则里加一行"派发前先查速查表，未命中再回退到自由探索"，让规则强制兜底。**不加兜底机制就不要做 A** —— 否则无效投入

#### 杠杆 C — 大文件锚点目录（推荐次做，与"重构方案"互斥）

- 形式：在 6 个 1000+ 行重文件顶部加注释目录，列出功能段标识 + 起始行段 + 入口函数索引
- 作用：让 brief 引用时可以精准定位章节，不用整段贴；间接降低 inline 体量
- 投入：每文件 30 min–1 h，6 个全做要 4–6 h
- 单次派发预计节省 1–3 min（仅在涉及重文件时）
- 风险：接近零（不改行为，只加注释）
- 与重构方案互斥：如果将来执行了重构（拆分这些大文件），C 会被覆盖。建议先做 1–2 个验证收益，再决定是否做完所有 6 个

#### 杠杆 B — 契约块仓库（暂缓）

- 形式：把高频不变量（AppState 同步约束、FeatureStore 边界、UI-only 禁区、持久化一致性）预制成可复用短块，brief 写作时引用
- 作用：保护"brief 瘦身"路径（用契约句替代原文 inline）的准确性，避免每次重写契约句导致语义漂移
- 投入：3–5 条起步 1–2 h，覆盖 15–20 条要半天到一天
- 长期维护成本：每月 1–2.5 h（核对契约块与代码漂移；漏查 → 后续派发基于过期契约出错）
- ROI 判断：每次派发节省 1–2 min，按月维护成本反推需 60–120 次派发/月才回本
- **当前评估**：派发频率不够，**暂缓**。等 A 上线一段时间、派发频率提升后再重评

#### 重构方案 — 拆分剩余 6 个 1000+ 行重文件（独立判断，不强行立项）

- 形式：把 store/state 层超 1000 行的重文件按职责拆成多个聚焦小文件
- 作用：从根本上消除大文件，inline 体量直接下降；A、C 的提速效果都是绕过此问题
- 投入：每文件 4–8 h（含测试与回归验证），6 个全拆 24–48 h
- 整体派发耗时可能压到原来 50–60%（**前提**：拆得职责清晰，让一个改动只触 1–2 个小文件；若拆完一个改动反而要 inline 更多小文件，inline 总量未必降）
- 附带收益：可读性、可测试性、可维护性提升 —— 这些大文件本身违反 Feature Store / 分层架构原则，是已存在的架构债
- 风险：中等。剩下的 6 个全是核心高耦合 store/state（区别于 5.5.1 已拆完的 4 个 UI 大文件），拆错就是 bug 来源；运行时行为（状态同步、异步顺序、SwiftUI 重渲染）容易在拆分时漂移；不可逆
- **拍板原则（重要）**：不要以"派发提速"作为重构动机，那个动机太弱。立项前提是**这些大文件本身在日常开发已成为维护痛点**（改 feature 时反复踩坑、bug 集中、新人/AI 反复读不懂）。如果痛点存在，作为独立"架构债清理"项立项，理由是债务而非派发提速；如果只在派发场景痛，A+C 就够。这条决策由 Jack 在日常开发体感积累后单独拍板，不绑定本期 5.1.6 节奏

**执行优先级与决策树**：

1. **第一步：A + 强制兜底**（投入 1–2 h）。同时改 `dispatch.md` 或 `CLAUDE.md` 加"派发前查速查表"硬规则。**两步必须打包**，分开做就是浪费
2. **第二步：A 上线后跑 2 周观察实际节省**。如果节省 ≥ 10%，进入第三步；如果几乎无感，停在 A，重新评估归因
3. **第三步：先做 1–2 个 C**（挑最高频被改的重文件起步）。验证收益再决定要不要做完所有 6 个
4. **B 长期观察**：派发频率达到月 60+ 次时再启动
5. **重构方案独立评估**：与本期解耦，由日常开发体感驱动立项

**预期收益区间**（用作决策参考，不作为承诺指标）：

| 组合 | 派发耗时压到原来 | 投入 |
|---|---|---|
| 只做 A（含强制兜底） | 85–95% | 1–2 h |
| A + C（部分） | 80–90% | 3–5 h |
| A + C（全做） | 75–85% | 6–10 h |
| A + C + B | 65–80% | 14–20 h + 月维护 |
| 全做（含重构） | 50–60% | 40–70 h，跨多版本 |

**否决方案及理由**（不要后续 agent 推翻）：

- ❌ A 不配套强制兜底就单做 —— 速查表写完没人查就是白做
- ❌ 一次性 A+B+C+重构全立项 —— 投入过大、风险叠加；先低成本试错再加码
- ❌ 直接跳到拆文件方案不做 A/C —— "派发慢"作为重构动机太弱，重构请独立立项
- ❌ B 优先于 A —— B 维护成本高、ROI 不明；A 是无脑做的低风险投入
- ❌ 不写预期收益区间，让后续 agent 凭感觉评估 —— 收益区间是决策依据，不能省

**来源与实证**：归因与杠杆设计来自 2026-04-25 的双 AI 对抗讨论。Codex 实地查证报告（含 Sources 目录统计、规范文档密度核算、dispatch_log 抽样）当时落在 `tmp/2026-04-25-codex-dispatch-speed-opinion.md`，启动本期执行时如需可由 Jack 决定是否升级为 handoff 归档；不升级则随 tmp/ 例行清理。本节量化数字（194 文件 / 3.68 万行 / 6 个 1000+ 行 / 最大 1800 行）已自包含，不依赖原报告存活。

### 5.1.7 — 规则产物可演化层（Rule Provenance + Sidecar v2 + Recompute）

- [x] 双层 sidecar（`ruleSnapshot` 可重算 / `userOverrides` 永不动）+ rule provenance + Recompute UI（stale banner + dry-run preview + condition edit + source tooltip）。设计纪要：[history/v517_rule_provenance.md](history/v517_rule_provenance.md)。

---

## 5.2.x — Import 管线 + Inbox 逻辑/架构

### 5.2.0
- [x] 废弃 condition pattern 字段清理：temperaturePattern/currentPattern/fieldPattern 从 ConditionRules struct 删除，保留 JSON decode 迁移；Canonicalizer 迁移码精简；Handbook save 不再写入废弃 key
- [x] condition_aliases.json 定位厘清：bundled 文件未被引用（运行时从 Library sidecar 加载），已删除
- [x] Override 文件删除时静默复活修复：ensureUserFileExists() 从读路径移除，仅在用户保存时调用
- [x] Override 加载逻辑去重（RuleLoader + ConditionRulesHandbookStore）`[来源: TECH_DEBT_BACKLOG]` — 提取 SeparatedOverrideReader 统一读取层，消除 5 个 override 文件的重复解析

---

## 5.3.x — Workbench 逻辑/架构

### 5.3.0
_(预留)_

### 5.3.3 — 通用 Multi-Tab 渲染状态框架
- [x] 引入 `TabRenderState`：per-tab 显示覆写（图例位置、标题/轴标签覆写、图例标签覆写）统一为一个值类型
- [x] 引入 `TabRenderOutput`：per-tab 渲染结果（PNG + layout + manifestPayload）统一缓存
- [x] Pipeline Input 桥接构造器：`TabRenderState` + 共享设置 → Input
- [x] 3ω store 状态重组：5 个散落字典 + 7 个散落 Data → `[Tab: TabRenderState]` + `[Tab: TabRenderOutput]`
- [x] XY store 状态重组：同上模式
- [x] AHE store 适配：单实例 `TabRenderState` + `TabRenderOutput`
- [x] [Bug] 3ω 批量重绘丢失 per-tab 覆写（#1）— 结构性消除：覆写存于 per-tab state，重绘时从对应 tab 读取
- [x] [Bug] Legend 热区不跟随覆写后标签宽度（#4）— 结构性消除：layout 和 label 覆写来自同一 tab state
- [x] [Bug] 3ω 重绘后 manifest 缓存过期（#7）— 修复：style 重绘保留现有 manifest，不覆盖为 nil

### 5.3.2 — Plot Render Pipeline 统一
- [x] 提取 WorkbenchRenderPipeline：三 workflow 共用一条出图管线
- [x] 原始轴列名由 pipeline 统一保留，manifest 不泄漏显示覆写
- [x] AHE 内联渲染逻辑迁移至 pipeline
- [x] 3ω / XY renderer `_render()` 改为调 pipeline

### 5.3.1 — Plot Shell 能力扩展
- [x] 绘图模式扩展：支持多种渲染模式（连线、散点、点线等），用户可选择 fit 数据的绘图模式
- [x] 图表右键菜单 Copy PNG：analyze 出图后可右键复制图片到剪贴板
- [x] 图表字号可调：title、x/y axis title、x/y tick label、legend 的 font size 可通过 Chart Style disclosure panel 选择
- [x] Tick 密度可调：Chart Style panel 内 x/y stepper 控制
- [x] 图表 title 取消加粗（当前硬编码 bold）
- [x] [XY Rotation] 可选辅助线：tickbox 控制在 x=180 处绘制灰色虚线
- [x] [Bug] x/y axis title 对齐修正：应居中于 tick 区域（画板），而非整个 plot 视图
- [x] [Bug] y axis title 缺少括号内容：XY y title 固定为 Rxx (Ω) / Rxy (Ω)，stacked/center 信息不再放在 y title
- [x] [XY Rotation] 默认 y title 修改：Rxy tab → "Rxy (Ω)"，Rxx tab → "Rxx (Ω)"
- [x] Legend 默认值动态化：legend 内容根据 input sample 动态生成，取代当前硬编码 → 移至 5.3.4

### 5.3.4 — Legend 维度自动推断 + 视觉一致性
- [x] LegendDimensionResolver：数据驱动优先级链（temperature > substrate=energy=pressure > thickness），支持数值容差、自定义 chain
- [x] WorkbenchPlotPayload 扩展：legendDimension + reverseSeriesForLegend 字段（Codable 向后兼容）
- [x] Pipeline 统一 series 反转：stacked tab opt-in，非 stacked 不受影响
- [x] 删除 ThreeOmegaPlotRenderer / XYRotationPlotRenderer 分散的 .reversed()
- [x] 测试：16 cases 覆盖 resolver + pipeline + backward decode

### 5.3.5 — 数据点标签可调（字号 + 显隐）+ Copy PNG 分辨率档位
- [x] 全图点标签字号统一可调：点击图里任一点标签弹出已有 title/legend 那套字号选项面板（复用 `WorkbenchPlotCanvas` 的 editFontSizeKey + onFontSizeChange 通道，新增一个 key）；改动同步影响所有图的点标签
- [x] 点击数据点切换该点的标签显隐：复用现有 hit-test 机制扩展数据点命中；记录用结果中的位置 index，不绑温度（保持通用，未来其他场景也能用）
- [x] 持久化复用现有 Update Analysis：把"隐藏的点列表 + 标签字号"塞进现有 ThreeOmega Scaling pack 配置字段，Load Analysis 时按既有重画路径恢复，不新增存储入口
- [x] 触发范围：先 3ω Scaling Law（当前唯一使用点标签的 tab），其他 workflow 后续接入零成本
- [x] Copy PNG 分辨率档位 shell：右键菜单原 "Copy PNG" 拆为子菜单 "Copy PNG 1x / 2x / 3x"。1x = 渲染器原始像素（基线），2x = 当前默认（与 5.3.4 行为一致），3x 新增。机制做成通用倍率参数（scale factor 接到既有 PNG 输出管道一处入口），未来加 4x/任意倍率零改动；默认仍 2x，菜单不破坏既有快捷路径

### 5.3.6 — Plot Shell 曲线拖拽排序 _(已完成 2026-04-27)_
- [x] Shell 级能力：曲线拖拽排序属于通用 `WorkbenchPlotCanvas` / render pipeline 能力，不做成 3ω 或 XY Rotation 私有交互；workflow 只提供稳定 series identity 和当前结果数据
- [x] 唯一排序真相：每个可排序图维护一个 `seriesOrder`，语义固定为 bottom → top；初始值由 workflow 默认顺序生成（当前 stacked 图为温度升序），用户拖动后该数组成为唯一排序源，不再同时维护”温度排序”和”手动排序”
- [x] 拖动判定规则：用户拖动线条后，shell 根据每条曲线在 x=0 的截距判定上下位置；释放时以拖动后的截距位置重排 `seriesOrder`
- [x] Legend 跟随曲线顺序：legend 不保存独立顺序；渲染仍按 bottom → top 构建曲线，pipeline 统一投影成 legend top = visual top
- [x] 持久化：Save Analysis / Load Analysis / Pack restore 必须保存并恢复 `seriesOrder`；重新 Analyze 时先按已有 series identity 对齐旧顺序，新增曲线按 workflow 默认顺序补入，消失曲线剔除
- [x] 适用范围：先接入已有 stacked curve 图，机制必须保留为 shell 能力，后续 workflow 接入只需暴露稳定 series identity 与 opt-in 能力

### 5.3.7 — _(范围并入 5.3.6，2026-04-27)_

原计划将曲线身份存储从 5.3.6 拆分为独立版本，Jack 决策合并执行。
实施方案见 `docs/handoff/2026-04-27-5.3.6-series-identity-storage.md`。

---

## 5.4.x — Library 逻辑/架构

### 5.4.0
- [x] P1: 删除 LibraryCommandCoordinator，折叠 LibraryFacade `[来源: LIBRARY_ARCHITECTURE_AUDIT]` _(已在 5.1.1 完成)_
- [x] P2: 合并 LibraryMutationOrchestrator 到 LibrarySyncService，统一 diff 入口 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [x] P3: 从 FeatureStore 提取 workbench/measurement 投影、日志管理、编辑状态 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [x] P4: 简化 ViewModel，View 直接读 appState.library `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [x] P5: 拆分 LibraryView（1252行）为 4-5 个聚焦组件 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`

---

## 5.5.x — 全区域 UI 统一优化

### 5.5.0 — 跨区域一致性 + 设计基础设施
- [x] 字体可读性违规修复：9 处 `.footnote` 用于用户需读内容（Inbox 5 处、Library 1 处、Workbench 3 处），提升至 `.callout`+；3ω 缩放结果 alpha/beta/R² 从 `.caption` 提升
- [x] 折叠区块点击热区修复：Inbox/Library 的折叠箭头改为整行可点（对齐 features.md Disclosure Sections 规则）
- [x] 提取统一折叠区块组件：替代三区域各自的手动 chevron+HStack 实现
- [x] 统一字体梯度：提取 app 级字体常量，替代三区域各自内联/局部定义的标题字号
- [x] 统一间距常量：建立 AppSpacing 七级梯度，关键结构位置已替换，规则已记录
- [x] 按钮风格上下文统一：审查确认三区域已一致，四级规则（prominent/bordered/borderless/plain）已记录

### 5.5.1 — 大文件拆分
- [x] InboxView（~1250行）拆分：1237→64行 + 5 个独立文件
- [x] LibraryDetailSections（~990行）拆分：删除原文件，拆为 5 个聚焦组件
- [x] RulesHandbookView（~1072行）拆分：1072→764行 + 4 个独立文件
- [x] WorkbenchSharedComponents（~940行）拆分：897→10行（索引注释）+ 8 个独立文件

### 5.5.2 — 共享组件补全
- [x] Flow/Wrap 布局去重：FlowLayout 合并到 UI/FlowLayout.swift，删除 WorkflowRegistryView 中的重复实现
- [x] 纯图标按钮补 accessibilityLabel：13 处跨 7 个文件
- [x] 状态指示颜色冗余：审查确认现有实现已有文字/图标冗余，无需额外改动
- [x] MetadataViews 审查：MetadataValueRow 已被 22 处采用，无明显重复需合并
- [ ] 行/列表选中态统一：Inbox 用 List、Library/Workbench 用自定义卡片，选中态视觉和信息密度对齐（留待 UX 需求驱动）

### 5.5.3 — 文档补齐 + CLAUDE.md 瘦身
- [x] 创建 specs/04_UI_RULES.md：字体/间距/按钮/折叠/无障碍视觉规则
- [x] 创建 specs/06_PROJECT_ARCHITECTURE.md：代码放置、模块架构、管线、检查清单
- [x] CLAUDE.md 瘦身：SpinLab 专有内容下沉到 specs，CLAUDE.md 保留通用工程方法论，可跨项目复用


---

## 5.6.x — 预留

_(未分配)_

---

## 5.7.x — Docs 专项

### 5.7.0
- [x] CLAUDE.md 瘦身：已在 5.5.3 完成 — SpinLab 专有内容下沉到 specs/04 + specs/06，CLAUDE.md 保留通用方法论

### 5.7.1 — TASK_BOARD 引入 + 文档治理重构
- [x] 新建 TASK_BOARD + history/INDEX，退役 handoff/README + TECH_DEBT_BACKLOG，改 docs/README.md + 项目 CLAUDE.md + 全局 workflow.md；文档治理收敛为单一职责体系 → [`history/v571_task_board.md`](history/v571_task_board.md)
