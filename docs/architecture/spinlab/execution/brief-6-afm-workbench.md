# 任务 6 — AFM Workbench 改读标准数据与正式 Plot 保存

状态：Design Draft；基线 main `e85cb2d5`（#238 合并后）。前置：任务 5（#234，AC10 已通过）、#236 的 Library 使用体验收口。共同合同：[SKELETON](SKELETON.md) K5–K11；本任务继承 D6-B T04 的科研目标，但不恢复历史 G0–G5 开工门槛。用户已于 2026-11-26 确认保存语义与首期范围（见设计 §2.5：Live 正式 Plot 先行，Snapshot 与 V2 Pack 暂不支持并拆后续小任务）；原提交边界与恢复问题已通过静态复审；用户已确认统一 Plot 新建/替换及公共选择器（设计 F1），该补充仍待最终设计确认，未授权实施。

## 用户要什么

在隔离 V2 Library 中选择已入库 AFM Dataset → Analyze → 调整既有科学处理、图形显示 → 保存正式图 → 从正确 Sample 查到、重启后读回图及科学数值。操作仍以现有 Workbench 为主，不因内部拆分要求用户多按一次按钮。为任务 7 提供不依赖页面的同一处理、绘图和保存能力。

## 范围和边界

- V2 只通过 Task 5 的标准 Dataset ID 和 codec 读取；同一 Source 的多个 Dataset 明确区分，通道按稳定 ID 选取。归属从 Dataset → Source → Sample UID 推导；路径、原文件名和 Sample key 只是显示/追溯信息。保留来源缺失诊断与标准数据可读性之分。
- 复用现有 AFM 处理顺序、算法和 Heatmap；科学配置（channel、surface level、line flatten、zero）与显示配置（色标、颜色、标题、scale bar 等）分开。无页面调用使用显式有效配置，不能依赖上次 UI。处理后的矩阵、坐标、单位与诊断必须可核验，不能只有 PNG；不改写 Source 或 Dataset。
- 正式 Plot 使用 V2 公共资产登记、文件存储及直接 Dataset 依赖，不写 V1 chart/index、不另存 Sample—Plot 归属。用户未保存的预览不是正式成果。Live 输出和用户固定的 Snapshot 语义必须区分，Snapshot 本任务不支持（拆后续小任务，K11 的 Snapshot 首次消费者由其落地），须清楚标注未支持，不用 PNG/Pack 冒充；Task 7 不得依赖 Snapshot。
- 后台计算仅产生候选。发布/更新 Live 时，与修订和删除共享不可交错的正式提交点；核对依赖、有效配置、目标身份和当前状态，拒绝过时结果。样品当前 Result 格子不受影响。保存失败/中断可恢复，删除引用保护不得被绕过。
- V1 的 AFM Analyze/Pack/Restore 保持可用；AFM Save 仅 V2，旧格式库不可用并提示迁移；V2 未迁移旧入口不得写旧结构或静默回退到原始文件。V2 Pack 适用范围须在设计中明确，不能绕过正式资产机制。

## 验收

| ID | 必验内容 |
|---|---|
| AC1 | 从两份以上已入库标准数据（含同名文件或同 Source 多 Dataset 的合成夹具）选择准确 Dataset；正确 Sample/通道，重启读回；阻断 V2 raw parser 路径，Source 不可用时仍按任务 5 独立诊断。Dataset 损坏、删除或不可用不得假成功。 |
| AC2 | 同一 Dataset revision、有效科学配置下，Workbench 与无页面调用的矩阵、坐标、单位、诊断一致；以现有 AFM 回归及真实 IBW 的标准数据副本作数值基线，明确浮点/非有限值判据。 |
| AC3 | 反复切换处理从标准矩阵重算，不累计处理；换色/标题/色标/scale bar 不改变科学数值。缺失通道、失败渲染、选择/配置变更时不可把旧图配新配置保存。 |
| AC4 | 实际 Save 产生有内容的 V2 Plot；通过 Dataset → Source → Sample 查询，重启读出图、矩阵、诊断、实际有效配置及来源 revision；无重复 V1 index 或权威；输入数据和其他样品不变；Save 按 Library 记录匹配（上游 Dataset 集合+通道相同默认替换；从 Library “打开”的图在换 Dataset/通道前是明确替换目标且不留历史，否则默认新建），始终提供“替换”“新建”动作，共用按需弹出的 Plot Selector，支持同/异 Dataset 选择替换、相关性推荐及搜索（见设计 F1）；AFM 不做特殊限制，其他 workflow 暂不接入；PDF 导出时由矩阵重绘。 |
| AC5 | 确定性并发测试：A 捕获 v1，B 更正/更改有效定义/删除归属后 A 提交必须拒绝；A 先提交 B 后更新则相关 Live 过期；A→B→A 不绕过单调标记；手动替换到不同 Dataset 集合或仅不同通道（更新 `signal_locator`，随后匹配读到新通道）需确认；`snapshot_input` 与夹具行永不匹配；{D1} 默认替换与 {D2} 手动换入的竞态中前者被拒；手动替换时依赖与归属原子切换；目标被删或 revision 不符时 Save 失败并提供“新建”；同一保存回执丢失重试不重复；Sample 回收/恢复与发布、Library 切换与写权限失效竞态按设计 D 验证。更新须带 `expectedPlotRevision`：A、B 同读 rev1，B 先更新则 A 被拒；Dataset 删除或归属变 historical 时发布被拒。 |
| AC6 | 故障注入覆盖正式文件与 SQLite 发布、恢复及重试；无缺文件的 ready 图、重复资产、越权写入或误删未知文件。Source/Dataset 删除对真实 Plot按现行合同保护；设计覆盖用户如何独立管理不再需要的正式图。 |
| AC7 | AFM 只有一个 Save（V2 正式 Plot），旧格式库下该按钮不可用并提示迁移，不写旧结构；V1 Pack/Restore 及其他 workflow 的 V1 保存回归不变（见设计 §2.6-F0）、其他 Workbench 旧行为及 V2 写保护回归；当前交付 HEAD 的隔离 GUI 验收（合成数据＋经授权的真实 IBW 副本），含选择、处理、保存、重开与失败反馈，含 F1 选择窗口空态、推荐、搜索、同/异 Dataset 替换、取消不写入及窄窗口操作；生产内容哈希不变。 |

## 不做及开工

不新增 AFM 算法、不扩大全 Workbench、不建自动化执行器/预设（任务 7）、不做 AHE Result 写入（任务 12）、不迁移真实 Library（任务 11）、不解除未适配消费者的 V2 写保护。不引入新的跨进程锁、通用 DAG、编排或第二套资产系统。若正式 Live Plot 仍超出可审查范围，按设计审查及用户确认拆成最小可验收阶段；未满足任务 6 正式合同不得勾选完成。

先阅读 [初始设计与静态审计](design-6-afm-workbench.md)，按执行包 design 模式收敛；用户确认保存语义及兼容边界后，独立审查通过才进入代码 PR。实现时遵守 AGENTS、UI/Plot/Controls 合同及测试规则。合并实施时才在 Roadmap 勾选任务 6；真实 Library 不参与本轮。
