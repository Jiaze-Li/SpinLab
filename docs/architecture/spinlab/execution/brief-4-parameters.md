# 任务 4：Library Result Definitions 与 Sample 当前结果

从现有 PR #225 继续实施。前置：任务 1、3 已合并。**本任务替代旧的“手填 Parameter”方案，不要再实现一套与 Result 并存的 Manual Parameter。**

## 目标

用户在 Library 的 Result 管理工作区创建全库共用的科研结果格子（Definition），在每个 Sample 中为这些格子填写**当前数值**。手工输入与将来 Workbench 写入同一个格子；输入来源不决定数据类型。只保留用户明确确认的当前值，不自动同步和保留日常历史。

## 两层数据与最小范围

1. **Result Definition（Library 级）**：稳定、不含业务含义的 `definitionID`（推荐 `rdef_`）；名称/物理量标签（如 `Rxx`、`R_AHE`、`alpha`）、单位（例如 Ω）、可选的用户自定义限定文字（如 `300 K`、`30° device`）。一条 Definition 供所有 Sample 复用，语义由用户定义，不要求填写拟合温区、方法或来源。不把限定文字强行解释为已核验的测量条件。
2. **Sample Result Value（Sample 级）**：以该 Sample 的正式记录和 `definitionID` 唯一定位，只存有限数值及必要的更新校验信息。一个 Sample、同一 Definition 只有一份当前值。0 是有效值；未填写则不保存条目。无需为每个当前值另造独立 `res_` ID。
3. **Result Manager 工作区**：用户能新增、查看、修改 Definition（包括限定文字），并在 Sample 中看到定义的空槽位、填写、确认覆盖、清空数值。增加 Definition 不应遍历并修改所有 Sample 文件；已有 Definition 的语义字段变更需提示已填写 Sample 的影响，不得静默改物理含义/做单位换算。
4. 例如 `Rxx @ 300 K (Ω)`、`Rxx @ 30 K (Ω)`、`R_AHE @ 5 K (Ω)`、`alpha @ 30° device` 都只是用户创建的不同 Definition；**不预置硬编码的完整物理指标表**，也不规定所有材料必须使用同一拟合区间。
5. **确认与权限**：输入数字不保存；用户确认后写入（人工决定可否接受，系统可以提醒不匹配，不能擅自替用户裁定）。保存失败、过期草稿、只读 Library、无效数值或损坏文件必须拒绝覆盖并明确报告。

## 存储与现有功能边界

- 当前 V1 在 `Library/_spinlab/result_definitions.json` 保存唯一的全库 Definition Catalog；在现有 `sample.json` 的新可选 `results` 字段保存各 Sample 的当前值（按 `definitionID` 关联）。这只是最小实现方向，具体 Codable 形态由实现者选；不得把当前值再复制进 SQLite / Registry / `numericTags` / `measurement_data.json`。
- 旧 `sample.json` 没有 `results` 仍正常读取；无 `sampleUID` 的历史 Sample 也能在自己的正式记录内填写；UID 补发/文件迁移不属于本任务。
- Definition Catalog 不存在时表示尚未创建定义；**损坏或不可读不能当空 Catalog 覆盖**（K13）。删除已使用 Definition 不得静默丢掉任何 Sample 值；本任务可先仅允许删除未使用的定义。
- 新建/修改 Sample Result 不触发 Registry/XLSX 写回。Registry Apply、旧样品合并、Sample 元数据编辑、手机拾取和重启不能抹掉 `results`；须检查 `LibraryDiffEngine`、`LibraryStore+Drawers`、Sample 编辑保存路径。
- 任务 9 的“空样品”判断必须把**已填写的 Result Value**视为有数据（进入废纸篓需二次确认）；仅存在空 Definition 不算该 Sample 有数据。永久删除仍沿用当前 V1 安全边界。
- Batch 生长条件由 Batch 持有科研权威；本任务不改变 `LibraryBatch/LibrarySample.numericTags` 重复状态，留给任务 10。Measurement Conditions 仍随仪器数据/Sidecar 管理；Result Definition 的限定文字不自动回写 Sidecar。
- Workbench 计算得到的数值只是候选，**不能自动覆盖 Sample Result**。任务 4 仅提供可复用的读写接口；首个 AHE/RT/3ω 写入入口在任务 12 独立实施。Analysis Configuration 继续由 Workbench 管理，不强制存入每个 Sample Result。
- 不引入 SQLite、新的 Measurement/Device 实体、来源追踪、分析历史、自动重算、依赖图、批量旧库迁移或跨 Sample 自动选择。

## 验收（只在测试 Library）

1. 在 Library 新建 `Rxx @ 300 K (Ω)` 与 `alpha @ 30° device` 两个 Definition；多个 Sample 都能看到空槽位，磁盘未生成空值记录；新建第三个 Definition 不批量重写 Sample。
2. Sample A 写入 `Rxx @ 300 K = 520` 并确认；未确认改成 500 再离开仍为 520；确认后为 500。Sample B 独立保存 505；0 与未填写可区分。
3. 删除/清空 Sample A 的当前值，不影响 Catalog、Sample B 或任何 Source/Dataset/Plot；修改未使用 Definition 可用；试图删除已使用 Definition 不得丢值。
4. Registry 重新同步、修改 Sample 其他字段、重启、旧 `sample.json` 无 `results`、无 UID 的老 Sample 都可用；Parameter/Result 操作不写 XLSX，也不出现虚假 Registry 同步警告。
5. 只读 Library 禁止改 Catalog/数值；损坏 Catalog、保存失败、过期编辑必须 fail-closed；没有任何 Workbench 结果被自动写入。
6. 复核废纸篓空样品判断：有已填 Result 的样品需二次确认；只有 Definition 空格的不算有数据。定向测试、`swift test` 和 AGENTS.md 规定的收尾检查通过。

## 开工

本 Draft PR #225 的代码执行使用 `taskType: "code"`，本文件全文为 `contractText`，`SKELETON.md` K1–K13 为约束。先核对现行 Swift 路径；若旧逻辑会覆盖新字段，必须先保障兼容与防丢失。实现和测试在本 PR 完成；通过 Review、用户验收后才将 Roadmap 的任务 4 标为 `[x]`。不触碰用户真实 Library。
