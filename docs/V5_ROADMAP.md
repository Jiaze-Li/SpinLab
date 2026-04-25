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
| 5.7.x | Docs 专项 | 收集中 |

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

**状态**：`[~]` 已规划进行中（4 个会话拆分，工作量 16–20 h）

**动机**：4·25 事故暴露规则架构散落多文件、bundle 与 runtime schema 不一致、半成品迁移路径并存（如代码层齐全但永远不会真存在的 `conditions_rules.json` 分文件）。同一份概念多处存放、隐式"分文件赢"约定、bundle 与 runtime 没有自动同步——任何一处改动都可能让另一处静默漂移。需要从根上修。

**顶层原则**（已上升为 App 顶层规则，待写入 `docs/philosophy.md`）：
> "你看见的，就是 App 设置的。" 所有规则——包括平时几乎不改的——都必须在 UI 里看得见、改得动。

**拍板方案**：

1. **后台架构**：一类规则一个文件，没有"主文件 + 分文件"叠加。当前 6 类规则 → 改完后 6 个文件，每份在仓库 `Sources/SpinLabApp/config/` 和 runtime `~/Library/Application Support/SpinLab/config/` 各放一份，**两边字节级一样**。6 类清单：
   - 文件名解析规则（含 conditions / 单位 / token map）
   - 样品 ID 识别规则
   - 工作流匹配规则
   - 衬底名归一化规则
   - 测量标签规则（识别 AMR/PHE/Rxx/Rxy 等测量种类）
   - 工作流 ID 生成策略（`preferredAlphabet` / `fallbackPrefix`，目前 2 个参数）

2. **UI 架构**：单一"规则管理"面板，6 个分区/Tab 对应上述 6 类。入口在 Inbox 中间列「Inbox Operations」标题旁的**文字按钮**（不做全局菜单入口）。删现有 3 处分散入口：Workbench 顶部的独立 "Rules Handbook" 窗口 / WorkflowRegistryView 里的 "Match Rules" 区段 / InboxExplicitRulesSheet 弹窗。全部 6 类规则的编辑能力在新统一面板里**重新实现**，不要在烂地基上改良。其中 4 类已有 UI 实现可作功能参考（不是代码移植），2 类（测量标签 / 工作流 ID 策略）需要从零设计 UI。

3. **自动同步机制**：UI 一按保存 → 写本地 → 自动写仓库镜像，全程 App 自完成，用户不点任何"同步"按钮。反向同步（仓库版本新于本地，例如另一台电脑 pull 回来）：用**内容指纹（哈希）**判断，**不用文件 mtime**（git 不保留 mtime，会误判）。所有写入路径 atomic，写入前自动备份**最新一份副本**（覆盖前一份，不累积带时间戳的历史副本——只用于"刚保存出错"的回退兜底，不做 legacy 归档）。仓库目录指针机制：runtime 侧一个指针文件（一行 UTF-8 写仓库 config 目录绝对路径），找不到/为空就跳过镜像写入，不报错。

4. **迁移策略**：一次性迁完，**不留中间状态**。6 类规则的目标 schema 由本期**重新拍板设计**，不背任何旧格式包袱——迁移代码只负责读取旧文件内容、按新结构转写一次落盘，旧 schema 用完即抛，不保留任何兼容路径或并行加载逻辑。迁移前自动创建 `.backup-<ts>` 副本，迁移成功才删原文件。旧文件的 decoder 仅在首次启动迁移时使用，迁移完成后从代码中删除。

**否决方案及理由**（不要后续 agent 推翻）：
- ❌ 手动同步按钮 —— Jack 原话："我不想我按一下同步，我要自动同步。"
- ❌ 把不常改的规则（如工作流 ID 策略只 2 个参数、几年改一次）排除在 UI 外 —— 违反"看见即设置"原则；Jack 原话："这个 app 的最高规则就是我看见的就是 app 设置的。"
- ❌ 多入口并存或快捷跳转 —— 后台一处管理 → UI 也一处。Jack 原则："如果规则在后台是一处管理，那 UI 也做一个入口。"
- ❌ 在现有 UI 上改良叠新机制 —— Jack 原话："现在有的清理掉，全部重新做，不要在烂地里改良，好好做一个清楚结构的。"
- ❌ 入口放全局菜单 —— Jack 明确选择放 Inbox，不要改成 SpinLab 顶部菜单
- ❌ 用 mtime 判反向同步 —— git 不保留 mtime，会误判
- ❌ 分两阶段迁移（主文件 schema 升级 + 分文件合并各自一次）—— 避免半成品中间态

**拆分顺序（4 个会话）**：
- [x] **会话 1**：拆掉现有 3 处规则 UI + 删后端冗余分文件 / 半成品代码 / `scripts/sync_runtime_rules_to_bundle.sh` + 7 文件新 schema 落地 + 一次性迁移器 + 3 个未提交 bundle 改动同步。规则 UI 暂不可用（下一会话补）。`100e4cd`
- [x] **会话 2**：新统一面板骨架（Inbox 入口 + 6 分区路由）+ 接 4 类已有规则的编辑能力。`494ab17`→`e583534`
- [ ] **会话 3**：从零建"测量标签" + "工作流 ID 策略"两个分区的 UI。
- [ ] **会话 4**：自动同步引擎（双写 + 内容指纹反向同步）+ 完整测试 + 实机走一遍（启动 / 保存 / pull 后覆盖 / 回滚 / 指针文件缺失等场景）。

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
