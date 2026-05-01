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

### 5.1.5 — 规则管理统一 + 自动同步基础设施

**状态**：`[x]` 完成。s1–s12 全部归档。三本匹配深层统一（4 op + 单壳 + 数据扁平化 + v4→v5 迁移 + 28 regression tests）2026-04-28 落地。

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
| s11 [x] 已归档 | 三个匹配本子（Sample Identification / Workflow / Measuring Condition）UI + 字段命名 + Store 流程骨架抽 + Shell 容器抽：条目头 id、展开 displayName、scope 全删（含求值算法零改动 + 解码层最小兼容性扩展）、label→displayName 闭环（含 ConditionFieldCatalog 链路）；分 exec.A（schema decode compat + migration）+ exec.B（strategy + shell + 统一编辑器 + alias 清理）两段独立 commit；122 V515 全绿。 | [handoff/archive/2026-04-27-s11-design.md](../handoff/archive/2026-04-27-s11-design.md) |

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

##### s12 任务清单（2026-04-27 追加，三本匹配深层统一：数据扁平化 + 操作集 4 项 + 单壳）

**动机**：s11 完成了"UI 风格统一 + 字段命名"，但匹配数据模型仍是双层："一条规则 = 一个操作 + 一组数值"，操作集 6 种（equals / equalsAny / contains / containsAny / equalsOrContainsAny / regex），且 batch prefix 与 unit suffix 各自独立 UI（chip 列表 + 内部各自套不同 regex 模板）。Jack 在 2026-04-27 反馈：希望"匹配做成一个样子"——每行 = 左操作 + 右单值，所有匹配场景走同一个 shell。讨论收敛后确认：现存 workflow.json 无任何 regex 规则在用，starts-with（batch prefix 模板）+ unit-suffix（unit 模板）两个新操作能完整覆盖现有用例，可直接砍掉 regex 操作。Any 系列是语法糖，可拆成多行同操作表达。

**顶层原则**（沿用 5.1.5 顶层"看见即设置"+ s11"matching 走同一逻辑"，进一步收紧为）：
> 所有匹配场景共用一个 shell：每行 = 一个操作 + 一个单值。操作集封闭枚举，不开 regex 后门。

**拍板要点**：

1. **匹配数据扁平化**。原 `[{type, matchValues: [String]}]` 改为 `[{type, value: String}]`。一条规则 = 一行 = 一个操作 + 一个单值。多个值→多行同操作。
2. **操作集封闭为 4 种**：
   - `equals` — 完全相等
   - `contains` — 包含子串
   - `starts-with` — 输片段，系统自动套 `^<片段>\d+$`（原 batch prefix 用法）
   - `unit-suffix` — 输单位片段，系统自动套 `^-?\d+(?:\.\d+)?(?:<片段>)$`（原 unit 用法）
3. **统一壳替换 5 处调用**：Sample ID 三组（Materials / Treatments / Orientations）用 equals/contains；Workflows matchRules 用 equals/contains；Measurement Tag match 用 equals/contains；Measuring Condition token_map 用 equals/contains；Sample ID batch prefixes 用 starts-with；Measuring Condition unit_suffix 用 unit-suffix。所有标题统一叫 **Matches**。
4. **配置迁移一次性**：
   - `equalsAny` / `containsAny` → 拆成多行 `equals` / `contains`
   - `equalsOrContainsAny [A,B]` → 4 行（equals A、equals B、contains A、contains B）
   - 旧 `batchPrefixes: ["SL"]` → `[{type: "starts-with", value: "SL"}]`
   - 旧 `unitPattern` 反解片段 → `[{type: "unit-suffix", value: "mA"}, ...]`
   - 启动时 v4→v5 自动迁移 + 原子写回 + `.backup` 副本，迁移后旧解码路径删除
5. **regex 操作砍除**。基于现存 workflow.json 实测无 regex 规则在用。未来若出现 regex 需求，独立专项重开入口；本期不留 regex 后门
6. **匹配引擎改写**。原 `MapRule.match.matchValues` + `compiledMapRule` 求值逻辑替换为按 4 操作各自实现的 matcher（equals/contains 字面比对；starts-with / unit-suffix 内部即时拼 regex 走 NSRegularExpression）。AG6（s11 的引擎零改动）在 s12 不再适用——本期允许动引擎，但行为对等
7. **UI 单壳**：替换 s11 的 `UnifiedMatchRuleEditor`，新壳每行布局 `[操作 Picker(4选)] [单值 TextField] [删除]`，无嵌套展开层

**任务拆分**：

| 会话 | 主题 | 工作量 |
|---|---|---|
| s12-design | 设计稿对抗：4 操作集合 schema + 数据扁平化迁移路径（v4→v5）+ 引擎改写（matcher per type）+ 单壳组件接口 + 5 处调用替换清单 → handoff | 设计会话 |
| s12-exec | 执行：domain model 改 + bootstrapper v4→v5 迁移 + matcher 引擎改写 + 单壳替换 5 处调用 + UI 文案统一为 Matches + 测试同步更新 | 中（10–14 h）|

**关键 acceptance gate**（s12-exec 验收时必满足）：

- **AG1** 五处匹配区视觉与交互完全一致：每行 = 操作选择器（4 选）+ 单值输入框 + 删除按钮；无嵌套展开
- **AG2** 操作选择器只有 equals / contains / starts-with / unit-suffix 四项；regex 不在选项内
- **AG3** v4→v5 迁移：含旧 `equalsAny / containsAny / equalsOrContainsAny / regex / matchValues` / 旧 `batchPrefixes` / 旧 `unitPattern` 的 runtime 文件能解码并迁出（atomic + backup + 幂等）；迁移后旧解码路径从代码删除
- **AG4** 匹配引擎对现存所有规则的求值结果与 5.1.5 s11 完全一致（regression test）
- **AG5** 标题统一为 Matches；旧 "Match Rules" / "Match Values" / "Token Map" 字样从 UI 全清
- **AG6** Sample ID 的 batch prefixes 与 Measuring Condition 的 unit_suffix 走同一壳实例化，仅传入预设的操作类型限制

**否决方案及理由**（不要后续 agent 推翻）：

- ❌ 保留 6 操作 / 保留 Any 系列 —— Jack 拍板"做成一个样子"，Any 是语法糖可多行表达
- ❌ 保留 regex 作为第 5 操作 —— 现存配置无用例；保留 = 为不存在的需求加复杂度
- ❌ 暴露 regex 输入框给用户写正则 —— 违反"看见即设置"+ 对非技术用户不友好
- ❌ batch prefix / unit suffix 保留独立 UI —— Jack 明确"匹配做成一个样子"，独立 UI 违反单壳原则
- ❌ 数据保留双层结构、仅 UI 扁平化 —— 操作器跨行共享导致改一行影响多行，交互混乱
- ❌ 匹配引擎保持 s11 不动、仅 UI 拍平 —— 不可能：数据形状变了引擎必须跟改
- ❌ v4→v5 双 schema 并存兼容 —— 一次性迁完，不留中间态（与 5.1.5 F 项迁移策略一致）
- ❌ 引入 "starts-with" 之外的扩展操作（ends-with / regex-fragment / multi-segment）—— 本期只覆盖现有用例，不为假想需求开操作集

**来源**：2026-04-27 与 Jack 对齐。从 s11 完成后 Jack 发现"匹配数据形状不一致 + batch prefix / unit suffix 仍各自独立 UI"展开为本期专项。讨论历经多轮收敛：(1) 砍 Any 系列 → (2) 加 starts-with / unit-suffix 替代 batch prefix / unit suffix 独立 UI → (3) 确认现存无 regex 用例 → 砍 regex → (4) 收敛为 4 操作单壳。

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

### 5.1.6 — 架构梳理 + 索引文档（区块 / 层级 / 共享点）

- [x] 架构梳理 + 索引文档完成：218 个 Swift 文件完成区块 / 层级 / 共享点扫描，现行派发入口为 [architecture/INDEX.md](architecture/INDEX.md)，设计与实施摘要见 [history/v516_architecture_index.md](history/v516_architecture_index.md)。

### 5.1.7 — 规则产物可演化层（Rule Provenance + Sidecar v2 + Recompute）

- [x] 双层 sidecar（`ruleSnapshot` 可重算 / `userOverrides` 永不动）+ rule provenance + Recompute UI（stale banner + dry-run preview + condition edit + source tooltip）。设计纪要：[history/v517_rule_provenance.md](history/v517_rule_provenance.md)。

### 5.1.8 — Condition 统一规则列表（首条结构债清理）

- [x] Condition 不再 `unit_suffix` / `token_map` 二选一，统一为单一 `matches: [MapRule]` + schema v5→v6 一次性迁移；UI 删 segmented control，编辑器收敛到 `MatchRulesEditor`；`$MATCH` 输出锁定到 unit-suffix op（PR #61 Codex 评审守住）。设计与实施摘要：[history/v518_condition_unified_rules.md](history/v518_condition_unified_rules.md)。遗留 `NewRuleEntrySheet.RuleEntryKind` 死路径移交 5.1.9 收编。

### 5.1.9 — Measuring Condition 单位标准化 + NewRuleEntrySheet 死路径收编

- [x] Measuring Condition 单位标准化（标准单位 + 换算 + 精度清洗）+ NewRuleEntrySheet 死路径收编；v6→v7 schema 迁移；旧隐式归一化完全删除；47 tests 全绿。设计与实施摘要：[history/v519_condition_standardization.md](history/v519_condition_standardization.md)

### 5.1.10 — 架构合规审计多版本流水线规划

- [x] 5.1.11–5.1.14 多版本架构合规审计流水线规划入 ROADMAP（流水线总段 + 4 子段）+ TASK_BOARD（8 行进行中）；双 AI 协作收敛 14 条决策 + "不做"清单；AUDIT_PLAYBOOK 推迟到 5.1.11a 跑通后落地；纯文档零代码。设计与协作过程纪要：[history/v5110_audit_pipeline_planning.md](history/v5110_audit_pipeline_planning.md)

## 架构合规审计多版本流水线（5.1.11 – 5.1.14）

> 此段是 5.1.11–5.1.14 共享的设计纪要，落 ROADMAP 是为了未来打开任一子版本时不需要回头翻 tmp / handoff 才能理解决策。规划起点：`tmp/2026-05-02-claude-review-of-capability-threads.md`（含 Codex 收敛意见）。

### 动机

5.1.6 完成"区/层 → 文件 → 稳定职责"的全量映射（218 文件，0 暧昧），但**只回答了"这文件归谁"，没回答"它实际做的事是不是匹配那个层应该做的事"**。一年内 5.1.7/5.1.8/5.1.9 三轮持续在 Inbox 区改动，5.3.x 持续在 Workbench 区改动，Code Map 注释和实际代码必然出现漂移。如果不审，5.1.6 那张图会慢慢变装饰；如果用全代码 review 的方式审，体量太大不可执行。本流水线选"风险驱动抽样 + 按区分流水线"的中间路径。

### 任务范围（拍板）

- **只做"架构合规审计"**：验代码 vs Code Map 声明的层职责
- **不做** 跨区流程链索引文档（`CAPABILITY_THREADS.md`）：与 5.1.6 INDEX collaborator 段重复，会变第四真理源
- **不做** 扩展契约文档（`EXTENSION_CONTRACTS.md`）：暂留 deferred；只在审计中重复出现 extension pattern drift（多个新 workflow 都 fork shell / 多个 workflow-private plot 控件重复一样的事）时回头起独立版本

### 编号约定

- `a` = 审计（纯文档，零代码改动）
- `b` = 修复主轮
- `c/d` = 修复溢出（按需启用）
- 一个版本对应一个区（11=Workbench / 12=Inbox / 13=Library / 14=跨区 meta）

### 流水线顺序与理由

```
5.1.11ab  Workbench   ← 当前最活跃（5.3.x 持续改），漂移概率最高，前期收益最大
5.1.12ab  Inbox       ← 5.1.7-9 三轮重构刚做完，验证刚改完的边界
5.1.13ab  Library     ← 相对稳定，预计违规密度低
5.1.14ab  跨区 meta   ← 吃前三轮攒出的链级 + 边界不清问题
```

每对独立闭环：a 完成后才开 b；其他区的 a 可以并发开（11b 修着可以开 12a），但不强制。

### 判定口径（双 lens）

> 调用链优先 + 必要时验实际行为。纯调用链会漏：UI 文件可能调一个看似正常的 helper、helper 内偷做业务排序；Store 调 service 看似正常但实际拥有跨区策略；Repository import 看着无害但持久化路径里有业务分支。

每个抽样文件审两件事：

1. **调用链**：这文件实际调谁、被谁调；和 Code Map 声明的层职责是否匹配
2. **实际行为**：副作用、数据变换、ownership 行为；是否只做该层应该做的事

### 三分类发现 + 处置策略

| 类型 | 定义 | 处置 |
|---|---|---|
| **Violation** | 实际边界违规，存在 regression / 派发误判 / 测试性风险 | 入清单 → 喂给 b/c/d 或 14；产出表 disposition 列直接标注下一版派发信息（target version / 修复粒度 / 依赖关系），让 a 跑完时 b 的 ROADMAP 已成型 |
| **Drift** | code 与 docs 不一致但风险不高 | a 轮内**当场改 Code Map 注释**（已是 Session Closeout 第 6 条职责）；产出表加一段 `Doc Drift Fixed`，让审计历史可读，不入独立任务清单 |
| **Accepted Boundary** | 跨区行为是有意为之、与架构一致 | 简短记录（产出表 `Accepted Boundaries` 段）；如果有意为之但不显然，顺手补 docs |

### 跨区疑点侧栏（Cross-Region Doubts For 5.1.14）

每个 a 轮产出表必含此段，规则：

- **只记自然出现的**——不分支去做完整链调查
- **不在当区 b 修**——除非有明确单区 owner
- **喂给 14**——14 入场时把三轮侧栏合并为输入清单

理由：避免 Workbench/Inbox/Library 的 b 轮被链级问题污染范围；同时给 14 免费攒输入（前三轮等于在垂直审计的同时做了水平观察）。

### 抽样策略（风险驱动，不强求 218 全量）

每个 a 轮抽样池构造：

- 该区 Code Map 全部条目
- 关联到 5.1.6 `SP-*` 共享点的文件
- 关联到 5.1.6 `G-*` shell / 大文件候选
- 该区高风险层代表（UI / FeatureStore / UseCase / Service / Repository 各挑代表）
- 5.1.6 之后新增 / 移动的 swift 文件（pre-commit hook 强制登记的那批）
- 自 5.1.6 以来变更频繁的文件（git 触达次数高 + 与高风险共享重合）

11a 跑完一轮后再决定 12/13 是继续风险驱动还是扩面。

### Cross-cutting 归属规则

不立独立审计版本（理由：Cross-cutting 没有"作为单一区的边界"，本来就是给多区共用，违规形态分散）。归属：

- **共享 UI / Domain / helper 文件** → 按"主消费者"归 11/12/13（抽样池构造时归属判定写入 a 段产出表注释）
- **AppState / Registry / 全局协调器整体设计问题** → 归 14（属于跨区 meta）
- **5.1.6 附录 G `G-*` 候选**（G-002 AppState 1816 行 / G-008 WorkflowWorkspaceShell / G-010 RulesBootstrapper 等） → 按既有 ROADMAP 节奏走，**不**归审计版本

### c/d 溢出触发（四维度判断，不用违规条数硬卡）

启用 c/d 当：

- 影响层数：b 单轮波及 ≥ 3 个 layer
- commit 数：b 单轮 ≥ 5 个独立 commit
- 是否能独立 review：违规之间有依赖、无法独立 review → 拆 c
- 行为变更 vs 纯移代码：纯移代码可以合并，行为变更必须独立 → 拆 c

### AUDIT_PLAYBOOK 时机（不预先建）

> 方法没实战验证就正式化会变成束缚。

- 5.1.11a **之前**：方法说明只在 11a handoff / tmp 草稿中存在
- 5.1.11a **之中**：用方法跑 Workbench
- 5.1.11a **跑完**：从 battle-tested 方法落正式 `docs/architecture/AUDIT_PLAYBOOK.md`，定位"审计方法论"，不写 Code Map / 不写流程链 / 不和既有架构文档抢内容
- 5.1.12a / 5.1.13a：套 playbook，仅当有真实改进时回写 playbook（活文档）

### 验收 / 归档

- a 轮：产出表（Violation + Doc Drift Fixed + Accepted Boundaries + Cross-Region Doubts + Fix-Round Draft 五段）落 `docs/handoff/<YYYY-MM-DD>-<region>-audit.md`，归档时同步更新 `docs/history/` + `history/INDEX.md`
- b/c/d 轮：每个 Violation 消除有对应 commit；commit message 引用产出表行号
- 14 验收：前三轮 Cross-Region Doubts 全部有处置（修订 / 接受 / 推迟到具体后续版本）

---

### 5.1.11 — Workbench 边界合规审计 + 修复（架构审计流水线第 1 轮）

> 流水线起点。本版本同时承担"跑通方法 + 审 Workbench"双任务。

- [ ] 5.1.11a 审计：按上述抽样策略 + 判定口径在 Workbench 区扫一轮；产出五段表；纯文档零代码（Drift 改 Code Map 注释除外）
- [ ] 5.1.11a 收尾：从 battle-tested 方法落 `docs/architecture/AUDIT_PLAYBOOK.md`
- [ ] 5.1.11b 修复：按 5.1.11a Fix-Round Draft 入修；commit 拆批以"独立 review"为粒度
- [ ] 5.1.11c/d 修复溢出（按需启用，依四维度判断）

### 5.1.12 — Inbox 边界合规审计 + 修复（架构审计流水线第 2 轮）

> 套用 `AUDIT_PLAYBOOK.md`；针对 5.1.7-9 三轮重构后的 Inbox 区。

- [ ] 5.1.12a 审计
- [ ] 5.1.12b 修复
- [ ] 5.1.12c/d 修复溢出（按需启用）

### 5.1.13 — Library 边界合规审计 + 修复（架构审计流水线第 3 轮）

> 套用 `AUDIT_PLAYBOOK.md`；Library 相对稳定，预计违规密度低于 11/12。

- [ ] 5.1.13a 审计
- [ ] 5.1.13b 修复
- [ ] 5.1.13c/d 修复溢出（按需启用）

### 5.1.14 — 跨区 meta 修订（链级一致性 + 边界不清）

> 吃 11a/12a/13a 攒出的 `Cross-Region Doubts For 5.1.14` 侧栏 + 边界不清问题。两类问题合并处理（都属于跨区 meta，单独立版本不划算）：
>
> - **链级一致性**：跨区流程契约不一致（典型例：sidecar 字段在 Inbox 写入时和 Workbench 解读时语义有微差；Rules 改了 runtime 不刷新；protocol 设计造成跨区泄漏）
> - **边界不清**：Code Map 描述模糊导致多文件同时漂移；AppState / Registry / 全局协调器整体设计问题

- [ ] 5.1.14a 收敛：汇总前三轮 Cross-Region Doubts + 边界不清问题清单；提出修订方案（Code Map 措辞调整 / 区层重划 / 协调器重构提案）
- [ ] 5.1.14b 落地：执行修订方案；纯文档调整（Code Map）与代码调整（协调器重构）按修订类型拆 commit
- [ ] 5.1.14c/d 溢出（按需启用）：若 14a 设计问题清单 ≥ 10 条，事后拆多轮修订；触发条件留作 14a 收敛时事后判断，**不**在当前 ROADMAP 预留具体版本号

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

### 5.7.2 — [x] 文档结构按功能区×层重组：建立 inbox/ library/ workbench/ 三区子目录，退役 specs/03+00+06，coverage 55→125/218 → [`history/v572_s3_workbench_architecture.md`](history/v572_s3_workbench_architecture.md)

### 5.7.3 — 新增 Swift 代码登记 workflow（SOP 主路径 + Code Map hook 兜底）

**状态**：`[x]` 完成。218/218 Swift 文件全登记，pre-commit hook 接入，CLAUDE.md 4 步 SOP 落点，60 天验证窗口 remote agent 已排（trig_016KyxQa7BKYQA8Gvbvogm7R，2026-06-30）。设计思路 → [`history/v573_swift_code_registration.md`](history/v573_swift_code_registration.md)。

**动机**：5.7.2 把代码索引按"功能区 × 层"切到 13 份层文档，结构铺好但**新代码加进来时没有标准操作流程** —— 写代码者要靠记忆/翻 INDEX 才知道归哪个区哪一层、注释怎么写，加完容易忘记登记，前两次 `features.md` 漂移证明这种动力学下纯靠自觉守不住。需要把"新增 Swift 代码"做成**清晰可执行的 SOP**（标准入口），并由 pre-commit hook 兜底诊断 SOP 漏掉的情况（兜底，不是主角）。现有 `verify_architecture_code_coverage.sh` 已扫 `## Code Map` 段 + 校验文件存在 + 校验 INDEX 分子，但有三个空缺：(a) 新增 swift 时分母 fail 信息只说"总数变了"，不指出具体哪个文件；(b) 未接到 commit 路径；(c) 反向 orphan 检查（代码存在 → 文档必须列）粒度过粗。本期升级脚本 + 接 hook + 建 SOP，让 SOP 和兜底成对出现。

**顶层原则**：
> 新增 `Sources/**/*.swift` 走 SOP 主路径登记到对应区/层 `## Code Map` 段；pre-commit hook 是 SOP 漏掉时的可诊断兜底，给出具体未对齐路径与候选区/层提示。

**SOP 落点结构**（一处权威，两处指针）：

- **CLAUDE.md** ——  唯一权威，承载完整 4 步 SOP + 第 2 步 region/layer 判定树 + 第 3 步注释体例约束 + [HARD] 强制规则。AI 在执行任务时最稳定读 CLAUDE.md，操作闭环放这里。
- **`docs/architecture/INDEX.md`** —— 承载定位入口。现 `How To Use` 段只讲"找代码"，本期扩展加"加新代码：定位 region/layer 并进入对应 Code Map"小节，仅作为指针指回 CLAUDE.md SOP，不复制全文。
- **本 ROADMAP 5.7.3 段** —— 只写目标 / 拍板要点 / acceptance gate；**不复制 SOP 全文**，避免双索引漂移。

**拍板要点**：

1. **机制实质未变（同 r1 收敛）**：升级 `verify_architecture_code_coverage.sh` + pre-commit hook + `install_hooks.sh` 自举安装 + 双向集合差（unmapped / missing 两类输出）+ 动态 `actual_total` 取代 `EXPECTED_TOTAL=218` 硬编码 + INDEX 分子分母由脚本自动维护。
2. **commit gate 定位为兜底，不是主路径**。错误信息形态必须接得上 SOP：报"unmapped X.swift → 候选区/层：A / B / C → 在对应 md 的 `## Code Map` 段加一行 `- \`X.swift\` — <一句职责>`"，让卡住的人能直接跳回 SOP 第 2-3 步。
3. **SOP 4 步骨架（CLAUDE.md 完整版）**：
   1. 写代码。
   2. 决定归哪个 region / layer（**判定树见 CLAUDE.md**：先按消费者/行为归 region 不按物理目录；再按层归属 —— Input/parse/route/match/evaluate → Consume；rule authoring/persistence → Edit；pending/apply workflow → Workflow；跨域输出/sidecar/registry contract → Contract；跨两 region 时优先登记主 owner，collaborator 文档仅在长期契约时补）。
   3. 在对应 `architecture/<region>/<layer>.md` 的 `## Code Map` 段加一行：`` - `Sources/...swift` — <一句职责> ``（注释体例：**主动短句描述稳定职责**；不写条件从句、临时实现原因、测试结论、调用方信息）。
   4. `git commit`（pre-commit hook 校验）。
4. **机器锚点统一为 `## Code Map`**。规则、hook 提示、CLAUDE.md 文案禁止使用 "Source of truth" 作为段名或脚本锚点（仅可作概念描述用语）。`inbox/ROUTING_PIPELINE.md` 第 53–60 行那段 "Source of truth:" 叙述子段保留作为正文内容，不作机器识别目标。
5. **rename 不做特殊业务**。pre-commit hook 用 `git diff --cached --name-status --find-renames --find-copies` 做"本次 staged 涉及"提示，但**最终放行依据是双向集合差**：commit 后状态下 unmapped == ∅ 且 missing == ∅。R 状态自然分解为"旧路径 dangling + 新路径 orphan"两个普通问题。
6. **hook 分发与可绕过性诚实声明**。本地 git hook 必须 `scripts/install_hooks.sh` 自举安装；onboarding/CLAUDE.md 要求会话启动或首次提交前确认安装；`--no-verify` 永远可绕过 = git 本身限制；GitHub Actions 服务端兜底等仓库推 GitHub 再加（**不在本期范围**）；Claude Code PreToolUse hook 不作主机制。Acceptance 表述只能写"已安装 hook 的本地提交会拦截"。
7. **边界 + 豁免清单**。默认契约：`Sources/**/*.swift` 全部必须登记。**短期不引入豁免清单**（当前 Sources 无 generated/fixture）；未来出现 SwiftUI Preview helper / generated / 单文件 helper struct 时走显式 `scripts/architecture_coverage_exempt.txt`，每条带原因注释，且本身参与校验（豁免路径必须存在、不得与 mapped 重叠、删除时报 stale exemption）。
8. **不再做"一行人话"升级 / 降级**。现状 13 份文档已是"反引号路径 — 一行人话注释"格式；本期只 sweep 体例偏离条目，不重写注释。
9. **CLAUDE.md 改动 + specs/06 死指针修复**：(a) Engineering Quality 段加 [HARD]"新增 `Sources/**/*.swift` 文件必须登记到对应 `architecture/<region>/*.md` 的 `## Code Map` 段，由 pre-commit hook 强制（`scripts/install_hooks.sh` 安装后生效）"；(b) **新增 "Adding New Swift Code" 子段**承载完整 4 步 SOP + 判定树 + 注释体例；(c) Session Closeout 第 6 条加"改动 `Sources/` swift 文件 → 反查 Code Map 条目仍准确"；(d) 修复 L22 死指针 `specs/06_PROJECT_ARCHITECTURE.md` → 改指 `architecture/ARCHITECTURE_OVERVIEW.md` Build and Version Policy 段。文案使用 functional language。
10. **不扩张到自动登记 / PR 候选生成**。本期不做"AI 检测新 swift 自动加 Code Map 一行"或"PR 自动生成候选条目"——这是新机制需求，超出 brief 范围；写代码者按 SOP 手动登记，hook 兜底。
11. **全局 `~/.claude/docs/workflow.md` 暂不动**。本期不留全局占位段（占位本身是漂移入口）。验证窗口期满评估后再决定是否升级。

**验证窗口（[HARD] s1-exec 收尾时必排 schedule）**：

- **起算点**：5.7.3 s1-exec 最后一个 commit 落地当天。
- **窗口长度**：60 天。
- **回顾任务定义**（s1-exec 归档时与 `/schedule` 远程 agent prompt 一并写入）：
  - 扫 60 天内 commit hook 触发拦截次数（grep stdout log / git reflog）
  - 数 `--no-verify` 绕过次数（git log 比对 hook 应触发但未触发的 commit）
  - 列漏报案例（hook 放行但事后发现 Code Map 与代码偏离的 swift 文件）
  - 评 SOP 体感（CLAUDE.md SOP 是否真被读到 / 判定树是否够用 / 注释体例约束是否阻碍写作）
  - 输出形态：≤ 100 行报告 + 单行升级建议（`promote-to-global` / `keep-project-local` / `rework-and-extend-window`）
- **执行方**：远程 agent（`/schedule` cron 一次性触发），不依赖 Jack 或 Claude 主动记得。
- **若升级建议是 promote-to-global**：开 5.7.4 任务规划全局 `~/.claude/docs/workflow.md` 升级（不在本期 5.7.3 范围）。

**任务拆分**：

| 会话 | 主题 | 工作量 |
|---|---|---|
| s1-design | 设计稿对抗：(a) 升级后 verify 脚本接口（unmapped / missing 输出 + 退出码 + 错误信息接 SOP 第 2-3 步格式）；(b) pre-commit hook 调用形态；(c) `install_hooks.sh` 自举；(d) `smoke_architecture_code_coverage.sh` 4 场景接口；(e) CLAUDE.md "Adding New Swift Code" SOP 段文案 + 判定树 + 注释体例约束；(f) `architecture/INDEX.md` "How To Use" 加"加代码"指针段文案；(g) 验证窗口 `/schedule` agent prompt 模板（60 天后跑回顾任务定义）→ handoff | 设计会话 |
| s1-exec | 执行：升级 verify 脚本（双向集合差 + 动态分母）/ pre-commit hook / install_hooks.sh / smoke_architecture_code_coverage.sh / CLAUDE.md 改 [HARD] + 加 SOP 段 + Session Closeout 第 6 条 + 修 specs/06 死指针 / `architecture/INDEX.md` 加指针段 / 13 份 Code Map 段格式 sweep / **收尾排 60 天 `/schedule` 远程 agent**（AG11 强制） | 小（5–8 h） |

**关键 acceptance gate**（s1-exec 验收时必满足）：

- **AG1** 升级后 `verify_architecture_code_coverage.sh` 输出 unmapped + missing 两类清单，不再用 `EXPECTED_TOTAL` 硬编码。
- **AG2** pre-commit 调用同一脚本；任一清单非空（且非豁免）则退出非零并打印具体路径 + **候选区/层提示 + SOP 第 3 步注释体例提示**（让兜底信息接得上 SOP）。
- **AG3** `scripts/install_hooks.sh` 一键安装 pre-commit；onboarding 提示加入 CLAUDE.md。
- **AG4** `smoke_architecture_code_coverage.sh` 在临时 fixture/worktree 跑 4 场景：(a) 新增未登记；(b) rename 旧路径未删 + 新路径未加；(c) 删除 swift 但文档行未删；(d) 同 commit A/R/D 多类一次性报全部错误。退出码 0/1，不污染工作树。
- **AG5** rename 通过双向集合差天然覆盖，hook 不含 rename 专用业务逻辑。
- **AG6** **CLAUDE.md 含完整 SOP**：Engineering Quality 段 [HARD] 规则 + 新增 "Adding New Swift Code" 子段（4 步 + 判定树 + 注释体例）+ Session Closeout 第 6 条 + specs/06 死指针修复。机器锚点写为 `## Code Map`，**禁用 "Source of truth"**。
- **AG7** **`architecture/INDEX.md` "How To Use" 段加"加新代码"小节作为指针指回 CLAUDE.md SOP**，不复制 SOP 全文。
- **AG8** ROADMAP 5.7.3 段不含完整 SOP 全文（只引用 SOP 落点 + acceptance）。
- **AG9** Hook 不拦无关 commit（docs-only / 配置 / 测试 / 非 Sources 下 swift 改动）；staged 不含 `Sources/**/*.swift` 增删/重命名时直接放行不调脚本。
- **AG10** 13 份 architecture 层文档 `## Code Map` 段格式严格统一（`- \`Sources/...swift\` — <注释>`）；脚本对体例偏离能识别报错。
- **AG11** **s1-exec 最后 commit 落地当天调用 `/schedule` 排一个 60 天后的远程 agent**，prompt 含本节"验证窗口"段定义的回顾任务（拦截次数 / 绕过次数 / 漏报案例 / SOP 体感 / 升级建议），输出落到 tmp/ 或 docs/handoff/_pending/。该 schedule 编号与触发时间在归档 history/v573 实施摘要里登记。
- **AG12** `architecture/INDEX.md` 顶部 "Code coverage: N/M" 行由脚本自动维护（写回 numerator + denominator + last verified 日期）。
- **AG13** Acceptance 文档表述诚实：hook 拦截语义是"已安装 hook 的本地提交"；`--no-verify` 可绕过 + 远端兜底未上 = 已知边界。

**否决方案及理由**（不要后续 agent 推翻）：

- ❌ 用 "Source of truth" 作为段名或机器锚点 —— 实际锚点是 `## Code Map`，混用会让规则与脚本分叉。
- ❌ 把 5.7.3 包装成"建立新机制"叙事 —— 现有脚本已做一半工作，应叙述为"升级 + 接 hook + 建 SOP"。
- ❌ ROADMAP 5.7.3 段复制 SOP 全文 —— 双索引漂移；SOP 全文唯一权威落 CLAUDE.md。
- ❌ 把 commit gate 写成"主拦截规则"叙事 —— Codex r2 校准：兜底定位，不是主角；主路径是 SOP。
- ❌ rename 写专用业务逻辑 —— 双向集合差天然覆盖。
- ❌ 用 Claude Code PreToolUse hook 作主拦截 —— 不覆盖 Jack 手动 git commit。
- ❌ acceptance 写"hook 不可绕过"或"绝对拦截" —— `--no-verify` 现实让此承诺不诚实。
- ❌ 提前引入豁免清单 —— 当前 Sources 无 generated/fixture。
- ❌ 把维护职责落到"AI 自觉性"（无 hook 仅靠 CLAUDE.md 规则） —— 前两次 features.md 漂移证明纯规则不可靠。
- ❌ commit hook 同时拦"修改文件"（验证注释是否仍准确） —— 注释漂移概率低；强加变成走过场。
- ❌ 把 Codex 评审 gate（每次 PR Codex 复核 Code Map）写进本期 —— 推 GitHub 后再单独评估。
- ❌ AI 自动登记 / PR 自动生成 Code Map 候选条目 —— 新机制需求，超本期 brief 范围。
- ❌ 全局 `~/.claude/docs/workflow.md` 提前升级或加占位段 —— 占位本身是漂移入口；验证窗口期满再决定。
- ❌ 60 天验证窗口靠 Jack 或 Claude 主动记得 —— 必须远程 agent `/schedule` cron 触发，否则两个月后必忘。
- ❌ 把 `EXPECTED_TOTAL` 继续硬编码 —— 是漂移源不是防漂源。

**来源**：2026-04-30 与 Jack 对齐。讨论收敛历经：(1) 三道闸 + 一行人话升级提案 → (2) Codex r1 评审 reject-and-rework，暴露事实错误（机器锚点是 `## Code Map` 不是"Source of truth"；Code Map 现已是"路径 + 一行人话"格式；现有脚本已半套实现）→ (3) 重写为"升级现有脚本 + 接 hook + 双向集合差" → (4) Jack 校准目标"机制保证未来新代码加入流畅，规划 workflow" → (5) Codex r2 评审 adopt-with-fixes，确立"SOP 主路径 + hook 兜底"叙事、"一处权威 + 两处指针"落点结构、SOP 第 2 步判定树必填、第 3 步注释体例约束 → (6) Jack 提"验证 1-2 个月后再考虑要排时钟提醒"，加入验证窗口 + AG11 强制 `/schedule` 远程 agent。Codex 评审 artifacts：`tmp/5.7.3-codex-review.md`（r1）+ `tmp/5.7.3-codex-review-r2.md`（r2）。
