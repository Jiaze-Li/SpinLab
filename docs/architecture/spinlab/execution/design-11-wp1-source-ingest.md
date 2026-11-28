# Task 11 WP1 — 测量上下文、通道归属与 Source-only（设计入口）

基线：`main@5f8831a43589c7211a29f33c042beecccc0636b2`，总体设计 [PR #247](https://github.com/Jiaze-Li/SpinLab/pull/247) 已合并。2026-11-28 用户授权基于 #247 开启 WP1 独立设计 Draft。

**阶段：设计，不实施。** 以 [design-11 §4.2 WP1、§5.1–5.1c](design-11-v2-migration-readiness.md)、[brief-11](brief-11-v2-migration.md)、[SKELETON K5/K7/K12/K13](SKELETON.md) 与 [AGENTS](../../../../AGENTS.md) 为合同；不重做 Task 11 总体设计。本页为待完善的设计入口，不是已验收的实现方案。

## 1. 本包目标与边界

使 V2 Library 可独立于 Workbench 分析能力管理原始科研文件，并为 WP2–WP4 提供同一套测量上下文、归属和数据入口。沿用已确认的三个原则：

- 测量上下文随 Source 同一提交点持久化，记录用户确认的 workflow、通道与物理角色、条件及来源（rule/manual/fallback）、测量时间、原始文件名、源文件 mtime、旧路径（仅记录，不作身份）及必要规则/解释来源；可批量查询，唯一权威，不写进 Dataset 本体。未知不猜；有效通道属于 Source–Sample 直接关系，SQLite 为权威。
- 一份多通道文件涉及多个样品时，每个目标 Sample 各保存一份完整 Source 字节并登记各自有效通道；不共享跨样品所有权，不为节省少量磁盘空间跨样品去重。原始文件不改写，不将其他样品的信号暴露为本样品可分析通道。
- 合法原始文件在无适配器或标准化失败时可明确地 Source-only 入库（零 Dataset），仍受通用身份、归属、完整性、查询及删除/恢复机制管理。失败原因与可分析性明确，不伪造 Dataset。MR 只保留数据分类，不另建 MR Workbench、解析器或兼容逻辑；旧 Measurement Set 不迁移、不新增集合字段。

WP1 不建设 WP2 表格 Dataset/PPMS/LVM/RSM 适配器、WP3 通用 Dataset 检索和列定位、WP4 AHE/Plot/Result 或后续 Workflow，不实施 WP0 备份（独立工作包）、WP8/WP9 迁移。保留 V1 正常使用、AFM 标准化/自动出图现有功能。只有实际共同合同变化才调整 SKELETON，不另设并行权威或任务看板。

## 2. 当前实现与待设计问题

以下为基线静态核对，设计者须继续按实际源码确认调用链和所有写入/查询消费者：

- `LibraryAssetService.swift:230–299`：SourceManifest 有原文件名、路径、字节数、哈希、入库时间；`ingestAsset` 需要 adapter、单个目标 UID，拒绝空 Dataset；现有 committed receipt 重放检查目标 UID。须设计零 Dataset 的显式状态、完整请求绑定、上下文与文件/SQLite 的同一提交点，复用已有 pending/committed/recovery 机制。
- `InboxArchiveApplyService.swift:481–580`：V2 无 adapter 即拒绝；只读单个 `v2TargetSampleUID`、一个 operationID，AFM intent 随入库提交。核对确认草稿、ApplyCoordinator、已有去重与 Library 显示，明确多目标/通道路由、每目标稳定重试身份、部分成功/失败后的队列与反馈，不让失败的写入冒充已入库。Source-only 不得触发分析或自动出图。
- `LibraryAssetDatabase.swift`：schemaVersion 当前为 2。真实库无 V2 数据（#247 Audit A 的既有证据），仍需明确测试/开发 V2 库的 schema/旧记录处理：安全升级或明确拒绝，不能把缺失上下文解释为虚构的测量事实。核对实际写租约、commitLock、删除闭包、恢复与批量查询。
- 设计时区分：适配器缺失/标准化本身失败（原始文件仍可保全）与文件不可读、归属非法、哈希失败、持久化失败、写租约丢失等真正入库失败；不能用笼统 catch 降级掩盖后者。原始字节和 mtime 的采集与验证边界需明确。
- 核对同样品复用既有 Source、再次尝试标准化、上下文冲突的处理。现有 Source ID 和原始字节不改变；重试不重复登记；为后续补生成 Dataset 保留必要公共接口/语义，但不提前实现尚无消费者的通用转换引擎。
- 界面只需最小必要变动：确认目标 Sample/有效通道、明确原始文件已保存但无标准 Dataset及原因、Sample 中可查看/定位 Source。不要为 MR 或 Source-only 新造页面、复制 Library 管理逻辑。设计明确用户选择、提示与不可执行的操作；未知科研角色仍未知。

## 3. 设计交付与实施验收合同

Worker 在本页完善实际源码证据、最小数据结构/唯一权威、接口与模块职责、状态/事务/恢复、UI 行为和实施顺序。区分已确认的产品/科研原则、代理技术决定、真正需要用户确认的事项。设计成果应给出以下可执行验收的具体入口、夹具和预期结果；本 Draft 不宣称功能已实现。

| 验收 | 后续实施必须证明 |
|---|---|
| AC1 上下文 | 确认的 workflow、有效通道/角色、条件及来源、时间、mtime、原名、旧路径按值往返；未知不猜；批量查询可用，单一权威，无重复存储；旧 AFM 记录处理明确。 |
| AC2 多目标 | 同一多通道文件归两个样品，两个 Source ID、完整字节相同，各自有效通道与归属正确；无跨样品共享/误读；部分失败与重试不会重复、错写或遗失待处理目标。 |
| AC3 Source-only | MR/其他无适配器、适配器明确失败的可读原始文件可保存且有原因、零 Dataset；重启后归属/内容/状态可读；不可分析、不自动出图；真正持久化失败不报告成功。 |
| AC4 生命周期与恢复 | 沿用资产事务、写保护、删除/恢复与依赖规则；上下文随 Source 处理。故障注入覆盖提交中断、重放、重复请求与请求冲突，不能留下半状态或孤立关系；跨库/只读拒写；为后续生成 Dataset 保持同一 Source 身份。 |
| AC5 回归与交互 | V1 日常路径和 AFM 入库/自动图不回归；隔离 V2 库 GUI 验证多目标确认、Source-only 显示/查看、失败反馈、重启读回及删除/恢复；不新增旧分组机制，不为 MR 建专项分析。 |
| AC6 设计收口 | 按 Deliver 现行流程完成独立设计审查并明确未验证事项；后续代码 PR 另行授权，按 AGENTS 验收。Task 11 仍未完成，设计不改版本。 |

所有开发/运行证据只使用隔离合成夹具；真实 Library 不读取、不修改、不迁移。设计 PR 不修改 Swift、schema 或 AppVersion，不自动合并。WP0 可另开独立任务，不阻塞 WP1 设计。