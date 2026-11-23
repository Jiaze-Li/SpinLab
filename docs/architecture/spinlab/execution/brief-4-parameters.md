# 任务 4：手填参数，确认后直接覆盖

对应 D6-B 的 T02 中"结构化记录"部分，按"只有当前值"改写。照片和笔记不在本任务，另开。
做法已经定好，不需要单独的设计阶段。前置：任务 1 已合并。

## 目标

用户能给样品填写带单位的数值（首期只做电阻和一种明确的尺寸），修改时确认一次就生效，重启后还在。

**首期收口**：电阻 `resistance`（Ω，按明确录入的测量温度 K 区分，未指定温度是单独的未知条件，不默认 300 K）；样品长度 `sample_length`（mm，作用于整个 Sample）。这里的“温度”是电阻的测量条件，**不是** Batch 的 PLD 生长温度。现有 Registry “厚度”列有历史 `ps` 语义，本任务不借用该列、不推断薄膜厚度。

## 需求

1. 我能给一个样品填电阻（数值加单位），不需要有仪器文件。
2. 我把 520 Ω 改成 500 Ω：输入数字后还要点一次确认才保存。没确认就离开，值还是 520。
3. 确认之后当前值就是 500，不需要再做别的"采用"操作。旧的 520 不保留。
4. 同一个样品，10 K 下的电阻和 300 K 下的电阻是两个不同的格子，改一个不影响另一个。
5. 没填的格子显示为空，不显示 0。
6. 重启 App、重新同步 Registry 表格之后，我确认过的值不会被改回去。
7. 保存失败时明确告诉我，原来的值还在。
8. 程序的其他部分能按“哪个量、什么单位、什么适用条件”读到这个值，而不是去解析界面上显示的文字。
9. 一个字段槽位由 Sample 身份 + 固定字段键 + 明确条件定位；相同槽位只有一份当前值。10 K、300 K 电阻互不覆盖，未知温度不自动套用任意已知温度。数值 0 不等于未填写；拒绝 NaN、无穷、无效单位或条件。
10. 保存只修改指定 Sample 的手填 Parameter，不允许改 Batch 共同生长条件、已有 Registry 字段、测量文件或分析结果。已有仅包含其他字段的 Sample 编辑/同步不应抹掉手填 Parameter。

## 不做

- 修改历史、撤销、"采用"流程。
- 照片、附件、笔记。
- 分析结果自动写入参数（骨架 K9）。
- 完整物理量表、通用字段定义器、设备/Measurement 新实体、跨 Sample 参数继承、批次条件编辑。
- AFM/其他分析算法接入、Result 自动计算或自动改 Parameter、历史数据迁移、Storage v2 路径修改、SQLite。
- 为本任务新建历史版本/撤销体系或通用依赖图；未来真正使用该 Parameter 的计算须遵循骨架 K10 的结果失效规则。

## 代码现状（`main`，Agent 开工前须自行复核）

- `LibrarySample` 现有的 `metadata`（字符串）和 `numericTags`（按名字存的数字）没有单位和适用条件，表达不了需求 4 和 8，所以不能直接复用这两个字段。
- `LibraryRegistryParser.numericUnits` 中现有“厚度”列沿用 `ps` 的历史含义；不得将它重解释为样品长度或薄膜厚度。
- 样品元数据已有一条编辑路径，见 `docs/architecture/library/SAMPLE_METADATA_EDITING.md`：界面 → `LibraryFeatureStore+SampleEdit` → `LibraryMutationService` → `SaveLibrarySampleEditsUseCase` → `LibrarySampleEditService` → `LibraryStore`，数据落在 `sample.json`。
- 仓库里目前没有 SQLite；`Package.swift` 的唯一外部依赖是 CoreXLSX。
- 指标类数据另有一条路径：`PersistMeasurementDataUseCase` 写样品的 `measurement_data.json` 并维护 `latestIndex`。本任务不改它，但参数不要再造第三套。

## 已定的做法

- **参数存在样品自己的 `sample.json` 里，新增一个可选字段**，每一项是"字段名、数值、单位、适用条件"。旧的 `sample.json` 没有这个字段，照常读取。
- **沿用现有的编辑路径**（见上），不另造一套保存逻辑。
- **本任务不引入 SQLite。** SQLite 等到任务 5（第一次需要链接表）再加。
- **Registry 同步不碰这个新字段。** 同步只更新它原本管的字段；核对 `LibraryDiffEngine`、`LibraryStore+Drawers` 的样品合并/覆盖路径，保证 Registry 重同步、其他字段编辑和重启都不丢参数。纯手填 Parameter 的保存不触发 XLSX 写回，也不因 Registry 文件不可用产生“参数保存失败”。
- 新字段用可解码的类型化记录表达“数值 + 单位 + 精确条件”；首期仅支持 `resistance`（Ω；可带温度 K）和 `sample_length`（mm；样品整体）。不向 `numericTags`、`metadata` 或 `measurement_data.json` 同时写一份副本；不从旧字符串字段猜测或批量转换为新 Parameter。
- 现有编辑会话与写入保护继续生效：输入未确认不写盘，保存失败保持原值和草稿；已在别处更新的样品拒绝过期覆盖；任务 3 的只读 Library 不允许写入。
- **旧样品没有编号也能填参数。** 参数跟着样品自己的 `sample.json` 走，不需要先补编号。

## 我怎么验收（在测试 Library 里）

1. 给一个样品填电阻 520 Ω，确认。显示 520 Ω。
2. 改成 500 但不确认，切到别的样品再回来。仍是 520 Ω。
3. 改成 500 并确认。显示 500 Ω。
4. 给同一个样品在另一个温度下填一个电阻。两个值都在，互不影响。
5. 退出 App 重开；再同步一次 Registry。两个值都没变。
6. 仅编辑 Parameter，不改 Batch 字段、原有 `numericTags`、原始测量、分析图与 XLSX；无 Registry 来源时仍能保存且无虚假“同步失败”警告。
7. 已有旧 `sample.json` 没有新字段仍可读；Registry 合并/其他 Sample 字段编辑不能覆盖 Parameter；无效数值、损坏文件、只读 Library 与过期编辑均拒绝写入。

## 开工

分支和 PR：使用从最新 `main` 创建的 Task 4 Draft PR；实现代码、定向测试和最终 Roadmap 勾选在同一 PR 完成。
流程：以 `taskType: "code"` 调用 `reviewloop_begin`，本文件全文作为 `contractText`，`SKELETON.md` 的 K1–K13 作为 `constraints`。

1. 先核对"代码现状"一节。与实际不符，或"已定的做法"会破坏旧样品的读取，就停下来告诉用户，不要自己换方案。
2. 实现，先跑相关的定向测试，最后跑完整测试和仓库规定的收尾检查。
3. 推送，等评审机器人。
4. 在 PR 里把 `docs/V5_ROADMAP.md` 5.6.x 段对应的那一行勾上并写上 PR 编号。
5. 请用户按"我怎么验收"亲手走一遍。合并由用户决定。

不要加本文件和 `SKELETON.md` 都没提到的机制（锁、日志、重试、新的状态）。觉得必须加，先停下来说明是哪条需求需要它。
