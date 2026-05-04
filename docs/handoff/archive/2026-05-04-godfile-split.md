# 5.1.15 — God File 拆分（5 份 >1000 行 Swift 文件）

> **状态**：方案完成 (s1)
> **设计对抗**：Claude 方案 `tmp/split_godfiles_claude.md` × Codex 方案 `tmp/split_godfiles_codex.md`，对抗审收敛于 2026-05-04，5 处分歧由 AI 收敛 3 处 + Jack 拍板 2 处。
> **节奏**：B 节奏（3 轮分组，轮间严格串行）；Round 1 / 2 轮内并行，Round 3 串行。
> **硬约束**：用户可见行为零变化（Jack 2026-05-04 给的 hard gate："做好分析，不要回归了"）。

---

## 0. 总体原则（双 AI 收敛 + Jack 拍板）

1. **保 type identity**。5 份大文件全部走"同 class/struct + extension 跨文件分布"的拆法。理由：视图绑定 + cross-store 持有引用早已稳定，切碎 type 必引爆 SwiftUI 视图刷新和 nil dereference。
2. **不外提行为**。本批纯做物理分布，不顺手抽 UseCase / Service。任何"看起来该抽到 service"的方法本轮一律留原 type，作为 5.1.16+ 单独任务。
3. **每轮前置 characterization tests**（**Jack 2026-05-04 拍板**）。每个文件拆分前先对当前行为写 snapshot 断言（IO / state 转换 / migration 输入输出），拆分后跑 snapshot 验证零字节级回归。代价是每轮多 1–2 天，回报是反回归硬装备。
4. **跨 extension 可见性**：跨 extension 共享的 `private` 方法升级到 `fileprivate`（不够时退 `internal`），不放开到 `public`。computed property 一律留主文件不拆。
5. **`@MainActor` 显式标注**：每个新增 extension 文件顶部显式 `@MainActor extension <Type>`（即使冗余也写），避免 Swift 5.9 `@Observable` macro 展开时 actor isolation 推断分歧。
6. **回归门**：每轮拆分后必须 `swift test` 全绿 + `./scripts/build_desktop_app.sh debug` 重建 + 启动 app 跑主路径手动 smoke。

---

## 1. Round 1：RulesBootstrapper + LibraryStore（低风险打底）

### 1.1 分工

| 文件 | 实现方 | 理由 |
|---|---|---|
| `Sources/SpinLabApp/Import/Rules/RulesBootstrapper.swift`（1203 行） | **Claude** | schema migration 链知识密度高，需追溯 v1→v7 + s12 演进 |
| `Sources/SpinLabApp/Library/LibraryStore.swift`（1112 行） | **Codex** | 持久层模式重复但工作量大，Codex 执行速度优势对应 |

### 1.2 RulesBootstrapper 拆分（1203 行 → 1 主 + 7 extension）

主文件（保留 ~170 行）：
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper.swift` — orchestrates runtime rule migration and seeding

按 schema migration family + 生命周期 extension：
- `RulesBootstrapper+Seed.swift` — seeds missing runtime rule files from bundled defaults
- `RulesBootstrapper+MigrationOrchestration.swift` — coordinates schema migration reads, writes, and state files
- `RulesBootstrapper+MeasuringConditionMigration.swift` — migrates measuring condition schemas to v7
- `RulesBootstrapper+SampleIdentificationMigration.swift` — migrates sample identification schemas to v5
- `RulesBootstrapper+WorkflowMigration.swift` — migrates workflow schemas to v3
- `RulesBootstrapper+MigrationHelpers.swift` — normalizes legacy match specs and JSON values
- `RulesBootstrapper+MigrationFiles.swift` — records migration state, failures, timestamps, and hashes

外提的顶层类型：
- `RulesBootstrapperVerificationModels.swift` — validates migrated rule files against runtime decoders

### 1.3 LibraryStore 拆分（1112 行 → 1 主 + 9 extension）

主文件（保留 ~220 行）：
- `Sources/SpinLabApp/Library/LibraryStore.swift` — owns library filesystem persistence and node caches

按持久层资源类型 extension：
- `LibraryStore+RootAndIndex.swift` — ensures roots and builds indexes from filesystem state
- `LibraryStore+Drawers.swift` — creates, updates, deletes, and discovers drawer metadata
- `LibraryStore+Measurements.swift` — copies measurement files and projects applied sidecars
- `LibraryStore+MeasurementSets.swift` — persists measurement set groupings for samples
- `LibraryStore+Backup.swift` — merges library contents into backup destinations
- `LibraryStore+ChangeLogs.swift` — appends and reads sample and batch edit logs
- `LibraryStore+RegistryLogs.swift` — bridges registry XLSX manual and metadata logs
- `LibraryStore+PathsAndCache.swift` — resolves library paths and invalidates directory caches
- `LibraryStore+SidecarEnumeration.swift` — enumerates sidecar URLs and decoder utilities

### 1.4 Round 1 characterization tests（前置）

#### RulesBootstrapper

新增 `Tests/V5115RulesBootstrapperCharacterizationTests.swift`：
- v1 → v7 完整 migration 链：fixture → 期望输出（每条 schema 终态字典字面比较）
- `state.rules_schema_version >= 7` 但 measuring_condition 文件版本 < 7：触发回归 migration
- bundle seed 缺失：写入 default + 不覆盖现有 runtime files
- decode verify 失败：写 `.migration_failed.json`，不损坏现有文件
- 用户定义 displayName / id / match value 拆分前后字面不变（防"清理"误改）

#### LibraryStore

新增 `Tests/V5115LibraryStoreCharacterizationTests.swift`：
- `ensureRoot` + `verifyRoot` 在临时目录的 round-trip
- `syncIndexFromFilesystem`：legacy + prefixed batch 布局并存时索引输出字面比较
- `createDrawer` / `updateSample` / `updateBatch` / `deleteSampleDrawer` / `deleteBatchDrawer` 全流程在临时目录的 IO snapshot
- `sampleChangeLog` 已存在时 unreadable → 阻止追加（不静默覆盖）
- `measurementSets` 空集时删除文件 vs 非空写入
- `syncBackup` nested overlap：源/目标互为子目录拒绝
- 4 个 cache（DirectoryEntries / DecodedBatch / DecodedSample / FileList）失效时机断言

### 1.5 Round 1 回归风险与缓解

#### RulesBootstrapper
- **风险**：bootstrap() 主入口的 v1→v2→v3→...→v7 调用链顺序敏感；某个 step 输出是下一 step 输入；任何"拆开后调用顺序漂移"导致静默失败（v4 引入字段在 v5 假定已存在但实际为 nil）。
- **缓解**：bootstrap() 主入口保留所有调用链不动，extension 仅承载具体函数实现；characterization test 第一条覆盖完整 v1→v7 链。
- **风险**：`expandLegacyMatchSpec` 等共享 helper 被多条 migration 链共调；提到 `+MigrationHelpers` 后跨 extension 必须可见。
- **缓解**：共享 helper 改 `internal`。

#### LibraryStore
- **风险**：4 个 cache 字典跨多 extension 读写，必须保 single owner；任何 extension 复制 cache 引用会导致 stale read。
- **缓解**：cache 字段保留主文件，extension 通过 internal access 读写。
- **风险**：legacy batch layout migration 与 preferred prefix layout 的 path helper 拆散后产生不同路径。
- **缓解**：所有 path helper 保留主文件 fileprivate，不外提。
- **风险**：unreadable edit log 当前会阻止追加；拆分时不能把失败降级为覆盖新 log（违反 audit log append-only 不变式）。
- **缓解**：characterization test 覆盖 unreadable log path。

### 1.6 Round 1 回归验证 checklist

```
- [ ] characterization tests 全绿（拆分前先跑一次确认基线）
- [ ] swift test 全 244 例绿（基线）
- [ ] git mv → 物理分布
- [ ] 跨 extension 私有访问从 private → fileprivate / internal
- [ ] 每个 extension 文件顶部 @MainActor extension（如适用）
- [ ] swift test 全绿（拆分后）
- [ ] characterization tests 全绿（拆分后字面一致）
- [ ] ./scripts/build_desktop_app.sh debug 重建
- [ ] 启动 app + 首次干净启动验 RulesBootstrapper seeding
- [ ] 启动 app + 已升级 schema 路径验回归 migration
- [ ] 启动 app + Library drawer create / update / delete / sync 主路径手动 smoke
- [ ] 每 extension 文件登记到对应 architecture/<region>/<layer>.md `## Code Map` 段
```

---

## 2. Round 2：ThreeOmegaWorkspaceStore + LibraryFeatureStore（store 拆法定式）

### 2.1 分工

| 文件 | 实现方 | 理由 |
|---|---|---|
| `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`（1534 行） | **Codex** | 行为分组干净，18 个 MARK 段已切好 |
| `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift`（1167 行） | **Claude** | 与 SpinLabAppState facade 注入紧耦合，连续上下文有利 Round 3 |

### 2.2 ThreeOmegaWorkspaceStore 拆分（1534 行 → 1 主 + 11 extension）

主文件（保留 ~260 行）：
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` — owns 3w workspace state and task lifetimes

按 Workbench lifecycle extension：
- `ThreeOmegaWorkspaceStore+RTSelection.swift` — manages independent RT search state and restoration
- `ThreeOmegaWorkspaceStore+Selection.swift` — manages measurement search selection state
- `ThreeOmegaWorkspaceStore+FitRanges.swift` — manages scaling fit range editing state
- `ThreeOmegaWorkspaceStore+Analysis.swift` — runs ingestion analysis and commits run traces
- `ThreeOmegaWorkspaceStore+Scaling.swift` — computes scaling results from frozen ingestion state
- `ThreeOmegaWorkspaceStore+Rendering.swift` — rerenders plot tabs from stored tab state
- `ThreeOmegaWorkspaceStore+ManifestCache.swift` — snapshots manifest payloads and input identities
- `ThreeOmegaWorkspaceStore+Persistence.swift` — saves active charts and metrics into library artifacts
- `ThreeOmegaWorkspaceStore+RelatedCharts.swift` — loads related result references for chart overlays
- `ThreeOmegaWorkspaceStore+Pack.swift` — builds and restores analysis pack state
- `ThreeOmegaWorkspaceStore+Plotting.swift` — implements plot editing and active chart protocols

外提的顶层类型：
- `ThreeOmegaRenderedPlots.swift` — carries rendered 3w plot data and layouts
- `OverlaySnapshot.swift` — stores detached overlay data for restored packs

### 2.3 LibraryFeatureStore 拆分（1167 行 → 1 主 + 9 extension）

主文件（保留 ~240 行）：
- `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift` — owns library feature state and injected capabilities

按交互子流程 extension：
- `LibraryFeatureStore+Facade.swift` — exposes coordinated library commands through configured callbacks
- `LibraryFeatureStore+Settings.swift` — manages library root, backup, and prefix settings
- `LibraryFeatureStore+PreviewSync.swift` — prepares registry preview and sync review state
- `LibraryFeatureStore+DrawerSelection.swift` — manages drawer and browser selection transitions
- `LibraryFeatureStore+AppliedMeasurements.swift` — projects sidecars and measurement sets for selected samples
- `LibraryFeatureStore+Recompute.swift` — manages stale sidecar count and recompute preview flow
- `LibraryFeatureStore+Logs.swift` — loads and updates library manual and metadata sync logs
- `LibraryFeatureStore+SampleEdit.swift` — saves selected sample metadata edits
- `LibraryFeatureStore+WorkbenchProjection.swift` — loads workbench result and measurement projections

外提的顶层类型：
- `LibraryFeatureStoreOutcomes.swift` — defines selection-change, save-edits, sync-decision, and registry-diff outcome enums

### 2.4 Round 2 characterization tests（前置）

#### ThreeOmegaWorkspaceStore

新增 `Tests/V5115ThreeOmegaWorkspaceStoreCharacterizationTests.swift`：
- `runAnalysis` 完整流程：selectedHits → ingestion result → tabs / R1 / R3 渲染输出 → currentRunTrace commit；其中 trace commit 必须只发生在 success 路径
- `runScaling`：已有 ingestion 后基于 fitRanges + v3Method 生成 scaling chart；多 fitRange 配置生成不同 chart identity
- pack restore：load pack 时不重新 ingestion；series order / hidden labels / legend / title override 字面恢复
- series order R1 / R3 reversal opt-in 在 stacked tab：alignSeriesOrder 字面输出
- RAHE method 切换不污染 Scaling Law 用的 v3Method
- clearPlot / clearResults 边界

#### LibraryFeatureStore

新增 `Tests/V5115LibraryFeatureStoreCharacterizationTests.swift`：
- dirty selection guard：sample edit dirty 时切换 drawer 弹 prompt；Save / Discard / Cancel 三分支
- facade callback 调用顺序：commit mutation → apply existing index → 刷新 preview groups → 保存 settings → 刷新 selection / projection
- sync review：no-change vs apply diff vs apply selected
- recompute stale dismissal：fingerprint 记忆
- root path / backup path / allowed prefix 更新触发的 cascade

### 2.5 Round 2 回归风险与缓解

#### ThreeOmegaWorkspaceStore
- **风险**：trace commit 是 features.md "sole trace commit point" 不变式；restore / rerender 路径误触发 commit 是直接回归。
- **缓解**：`commitRunTrace()` 拆完后只能保留在 `runAnalysis()` 成功路径和 save outcome 覆盖处；characterization test 覆盖 restore 路径不触发 commit。
- **风险**：series order / label overrides / hidden point labels 在 pipeline 反转前后映射错位（features.md "fit ranges are part of scaling chart semantic identity"）。
- **缓解**：拆分后跑 V531 / V534 / V535 / V536 测试套件全绿。

#### LibraryFeatureStore
- **风险**：unsaved sample edit selection guard 是一组原子行为（dirty draft / pending selection prompt / apply or cancel pending selection）；拆散后任一环节顺序变化引爆"切换 drawer 弹错框"。
- **缓解**：`+SampleEdit` + `+DrawerSelection` 之间的协作通过 store 主文件的 computed property 串联，不直接跨 extension 调 mutator。
- **风险**：facade 注入闭包路径在 Round 3 拆 SpinLabAppState 时也会动；Round 2 拆完后 Round 3 可能反复改边界。
- **缓解（硬约束）**：Round 2 拆 LibraryFeatureStore 时**严禁动 `configureFacade` 接口形态**——只做物理分布；接口重设计作为 5.1.16+ 单独任务。

### 2.6 Round 2 回归验证 checklist

```
- [ ] characterization tests 全绿（拆分前先跑一次确认基线）
- [ ] swift test 全绿（基线）
- [ ] git mv → 物理分布
- [ ] 跨 extension 私有访问升级
- [ ] 每个 extension 文件顶部 @MainActor extension
- [ ] swift test 全绿（拆分后）
- [ ] characterization tests 全绿（拆分后字面一致）
- [ ] V531 / V534 / V535 / V536 / Library 套件全绿
- [ ] ./scripts/build_desktop_app.sh debug 重建
- [ ] 启动 app + 3ω 主路径 smoke：搜索 → 分析 → scaling → save → load pack
- [ ] 启动 app + Library 主路径 smoke：root 设置 → preview → sync review → apply → drawer 创建删除 → sample edit save
- [ ] 每 extension 文件登记到 architecture/<region>/<layer>.md `## Code Map`
```

---

## 3. Round 3：SpinLabAppState（壳收尾）

### 3.1 分工（**Jack 2026-05-04 拍板：Claude 主拆 + Codex acceptance review**）

| 角色 | 责任 |
|---|---|
| **Claude** | 全部 11 extension 拆分实施 |
| **Codex** | acceptance review 全部 11 extension + 主文件 |

理由：AppState 是跨 region 壳，并行拆 extension 互相之间的可见性升级容易踩对方文件，串行更稳。Round 1 + Round 2 已经平衡了 4 个文件的工作量，Round 3 倾斜 Claude 主拆 + Codex review 整体仍接近平衡。

### 3.2 SpinLabAppState 拆分（1822 行 → 1 主 + 11 extension）

主文件（保留 ~280 行）：
- `Sources/SpinLabApp/App/SpinLabAppState.swift` — owns app shell stores and startup wiring

外提的顶层类型：
- `Sources/SpinLabApp/App/State/ApplyProgressState.swift` — models apply progress displayed by the app shell
- `Sources/SpinLabApp/App/State/PendingTagReadiness.swift` — describes pending import condition readiness
- `Sources/SpinLabApp/App/SpinLabAppContextProvider.swift` — provides registry and canonical lookup closures across stores

按跨 region 协调主题 extension：
- `SpinLabAppState+Navigation.swift` — coordinates route selection across app areas
- `SpinLabAppState+RepositoryProjection.swift` — applies repository streams into feature stores
- `SpinLabAppState+InteractionSnapshot.swift` — persists and restores cross-session interaction state
- `SpinLabAppState+InboxImport.swift` — coordinates import queue mutations and parsed hint refresh
- `SpinLabAppState+ApplyPipeline.swift` — applies confirmed pending imports into library drawers
- `SpinLabAppState+RegistryCoordination.swift` — coordinates registry loading and rule metadata refresh
- `SpinLabAppState+LibraryCoordination.swift` — coordinates library preview, drawer sync, and selection projection
- `SpinLabAppState+ImportDeduplication.swift` — computes duplicate import guards across app stores and library files
- `SpinLabAppState+RoutingPresentation.swift` — exposes routing presentation, drafts, and apply path for pending imports
- `SpinLabAppState+DrawerMatching.swift` — resolves library drawer matches and name-conflict checks for pending imports
- `SpinLabAppState+WorkbenchEntry.swift` — opens pending imports and archived records into the workbench

### 3.3 Round 3 characterization tests（前置）

新增 `Tests/V5115SpinLabAppStateCharacterizationTests.swift`：
- startup 顺序：rules reverse-sync → RuleLoader reload → repository projection → managed path migration → drawer load → interaction restore → pending match refresh，调用顺序快照
- Apply pipeline：registry lookup → pending draft → archive write → rollback on failure → audit → workspace prune，每步成功 / 失败覆盖
- duplicate guard：pending source path / original path / content fingerprint 三路缓存命中
- ContextProvider 9 个闭包字段 capture 语义：调用结果与拆分前字面一致
- navigate / openDeepLink 路由展开
- pendingDrawerMatchByID + nameConflictChecker 触发时机
- interaction snapshot restore + persist + flush 路径

### 3.4 Round 3 回归风险与缓解

- **风险（最高）**：startup 顺序漂移——init 中 7 个步骤的顺序不能变；任一漂移引发 stale projection / pending hint 丢失 / interaction restore 早于 store 装载。
- **缓解**：init 闭包**保留主文件不动**；extension 只承载方法实现；characterization test 第一条覆盖完整 startup 顺序。
- **风险（高）**：Apply pipeline 8 步任一环节移动后产生可见差异（Apply All 跳过 review-required 不变式 / per-file atomic + rollback / audit log append-only）。
- **缓解**：Apply pipeline 整体迁到 `+ApplyPipeline` 一个 extension，不跨多个 extension 拆步骤；characterization test 覆盖 success + rollback + skip review-required 三分支。
- **风险（高）**：`ContextProvider` nested struct 外提到独立顶层文件后 capture 语义需保字面一致；Swift 闭包 capture 语义本身不会因外提改变，但任何"清理"成 `[weak self]` 或调整 capture 顺序会引爆 Library / Inbox 一连串 nil dereference。
- **缓解（硬约束）**：闭包外提仅做"剪贴板搬运"，禁止任何"清理"/"优化"。
- **风险（中）**：private 方法跨 extension 调用——Swift extension 中 `private` 仅文件可见。
- **缓解**：所有跨 extension 共享的 private 方法改 `fileprivate` → 不够时退到 `internal`，不放开到 `public`。
- **风险（中）**：duplicate guard 缓存（`contentFingerprintCache` / `libraryImportedOriginalPathsCache`）跨 extension 读写。
- **缓解**：cache 字段保留主文件，`+ImportDeduplication` 通过 internal access 读写。

### 3.5 Round 3 回归验证 checklist

```
- [ ] characterization tests 全绿（拆分前先跑一次确认基线）
- [ ] swift test 全绿（基线）
- [ ] Codex 在 Claude 拆分前先 review 拆分计划（catch 早期边界错误）
- [ ] Claude 实施物理分布
- [ ] 跨 extension 私有访问升级
- [ ] 每个 extension 文件顶部 @MainActor extension
- [ ] swift test 全绿（拆分后）
- [ ] characterization tests 全绿（拆分后字面一致）
- [ ] Codex acceptance review 全 11 extension + 主文件
- [ ] Claude 修 review findings + 重新跑 swift test
- [ ] Codex 二轮 review 直至无新发现
- [ ] ./scripts/build_desktop_app.sh debug 重建
- [ ] 启动 app + 主路径 smoke：导入重复文件 / Apply Selected / Apply All 跳过 review-required / 规则保存后 pending hints 立即刷新 / 重启后交互状态恢复 / audit export
- [ ] 每 extension 文件登记到 architecture/<region>/<layer>.md `## Code Map`
```

---

## 4. 跨轮依赖链

| 轮 | 文件 | 编译依赖 | 语义依赖 |
|---|---|---|---|
| Round 1 | RulesBootstrapper | 无 | 无 |
| Round 1 | LibraryStore | 无 | 无 |
| Round 2 | ThreeOmegaWorkspaceStore | 无 store 依赖 | 软依赖 RulesBootstrapper（condition definitions / sidecar recompute）|
| Round 2 | LibraryFeatureStore | 强依赖 Round 1 LibraryStore 拆分稳定 | 直接持有 LibraryStore 实例 |
| Round 3 | SpinLabAppState | 强依赖 Round 1 + Round 2 全部稳定 | 持有 4 个 store + facade 注入闭包协作 |

**硬约束**：Round 1 → Round 2 → Round 3 严格串行（轮间不能并行）。轮内两文件可并行（Round 1 / Round 2）；Round 3 串行。

**软依赖警告**：Round 3 拆 SpinLabAppState 时若发现某条 facade 注入闭包路径需要调整 LibraryFeatureStore 接口，**必须回 Round 2 修**，不能 Round 3 边界打补丁。

---

## 5. 验收口径（每轮）

每轮结束 = 全部满足：

1. 轮内 characterization tests 全绿（前置 + 后置各一次）
2. `swift test` 全 244 例绿（无新增失败）
3. `./scripts/build_desktop_app.sh debug` 重建无 error
4. 主路径手动 smoke 通过（具体路径见每轮 checklist）
5. 每个新增 swift 文件登记到 `docs/architecture/<region>/<layer>.md` `## Code Map` 段（pre-commit hook 兜底）
6. commit 信息体例：`refactor(5.1.15-r{N}): split {File} into {N} extensions — characterization green, no behavior change`
7. Round 3 额外：Codex acceptance review 至少二轮无新发现

**单轮失败回退**：单轮拆分若 characterization 不一致 / 主路径回归 → `git reset --hard` 回到拆分前 baseline，分析根因，重写拆分方案，再次尝试。

---

## 6. 节奏估算

| 轮 | 工时（合计两人）| 关键路径 |
|---|---|---|
| Round 1 | ~4 天 | characterization tests 1.5d → 拆分 1.5d → 验收 1d |
| Round 2 | ~4 天 | 同上 |
| Round 3 | ~5 天 | characterization tests 1.5d → Claude 拆分 2d → Codex review + 修 1.5d |

总计 ~13 天（连续工作日）。轮间不强制隔时间，前一轮验收通过即可启动下一轮。

---

## 7. 不在本批范围（明确拒绝）

- 任何 type 拆碎（class → 多 class / struct）
- 任何行为外提到 service / use case
- 任何 facade 注入接口形态调整
- 任何"清理"用户定义 displayName / id / match value
- 任何 startup 顺序优化
- 任何缓存策略升级
- 跨 region collaborator marker 重新登记

以上全部作为 5.1.16+ 单独任务。

---

（本 handoff 完）
