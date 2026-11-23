# SpinLab 数据骨架

每次给 Agent 派任务都原样附上这一页。它由 G0 v1.4（§1–§3）和新数据库 v0.2（§0–§2）合并而来，冲突之处按用户 2026-11-11 的决定取舍。这里的内容不在单个任务里重新讨论；要改，先改这一页。

## 有哪几种东西

| 类型 | 含义 | 编号前缀 |
|---|---|---|
| Sample | 样品 | `smp_` |
| Result Definition | Library 全局定义的科研结果格子：名称、单位、用户指定的限定条件（如 `300 K`、`30° device`） | `rdef_` |
| Sample Result | 一个 Sample 在某 Result Definition 下被用户确认的当前数值；手填与 Workbench 写入是相同的数值槽位 | 由 Sample 记录 + `definitionID` 定位 |
| Source | 原始仪器文件 | `src_` |
| Dataset | 从原始文件整理出的标准数据 | `dst_` |
| Analysis output（后续） | Workbench 的计算候选/独立保存的分析成果（含 `Hc`、`R_AHE`、`alpha`、`beta` 等）；用户确认后才可写入 Sample Result | 独立计算成果沿用预留 `res_`；任务 4 不创建 |
| Plot | 图，连同画这张图用到的曲线数值 | `plt_` |
| Snapshot | 用户主动保存的一份定格 | `snp_` |
| Attachment | 照片、笔记 | `att_` |
| 链接 | 一行记录"哪个样品、哪个素材、什么关系" | 无 |

## Batch 与 Sample 是什么（实验室约定）

这一节定义词的含义，是本仓库对 Batch / Sample / Substrate 的唯一权威说法；其他文档不得另写定义，只引用这里。

- **Batch = 一次 PLD 生长。** 一次生长有一组固定的生长条件（温度、激光能量、氧压等），同一炉放入的所有衬底共用一个 Batch，如 `PN122`、`SRO xxx`。同样条件下隔一段时间再长一炉，是新的 Batch。
- **Substrate 信息有三项：** 处理方式（`o` 原始未处理、`b` 烘烤过〈backed〉、`HF` 酸洗过）、衬底种类（如 `STO`）、取向（如 `001`、`110`）。没有写处理方式，等同于 `o`；写不写对用户没区别。
- **Sample = 同一个 Batch 内、Substrate 信息相同的衬底，算一个样品。** 定位一个样品需要 `Batch + Substrate`，只靠 Batch 不够，因为一炉里有很多衬底。Sample 是物理层面的"不可区分类"，不是物质层面的一片：同炉里两片相同的衬底，现实中不同，但在现有实验条件下无法区分，记录里算一个 Sample。
- **Batch 不需要另外造不含意义的 UID**，以用户的 Batch ID 表示一次 PLD 生长的归属。Growth Parameters（生长温度、氧压、激光能量等已确认的共同生长条件）科研权威在 Batch；Sample 只通过 `batchId` 使用，不能独立修改同一生长事实。V1 的 `LibraryBatch.numericTags` 与 `LibrarySample.numericTags` 可能重复记载相同 Registry 值，这是兼容实现，**不等于两个权威**。Numeric Tag 只是旧字段容器，非所有 Numeric Tag 都是 Growth Parameter；字段归属参照 `LibraryFieldOwnershipRuleBook`，未知保持未知。任务 10 收敛新路径及读写权威；任务 11 迁移真实重复值，发现冲突须报告而非自动选边。

**这是人的约定，不是机器要强制的规则。** 创建样品是人做的事，人知道哪些衬底算一个样品。程序不判断两条记录是不是"同一个样品"，不做查重、不拦截、不合并、不补全处理方式（见 K2、K3）。只有出现真正需要这个判断的功能时才加，且应只作提示。同理，补全处理方式、合并旧库里按旧规则拆开的重复样品，都要等有具体功能需要时再做；合并会改动真实数据，还需用户决定并先备份。通用原则：机器做的事必须有具体用处，没有就不做。

历史说明：`docs/experiment-data-contract.md` §3–§4 曾记录过同一个模型（`sampleKey = batch|处理方式|衬底种类|取向`），并把"同炉同衬底无法区分"记为已知限制；这里把它确认为有意的设计，不是缺陷。现行身份以 `smp_` 编号为准。

## 规则

每条前面的编号供任务合同引用。

- **K1 编号永不变。** 编号在创建时生成（手写随机；手机提交由提交单号确定性换算，重复拉取不重复创建），之后不因改名、换批次、移动文件、重启、重试而变化。
- **K2 编号不含含义。** 编号不由名字、批次、衬底、路径或文件内容推算，也不拼接其他对象的编号。
- **K3 建几个就是几个。** 用户明确新建两次，就是两个样品，即使名字、批次、衬底完全相同。程序不判断两个样品在现实中是不是同一片。
- **K4 同一次操作不重复生效。** 同一次点击因卡顿、重试、重复触发被提交多次，只产生一个结果。
- **K5 素材和归属分开。** 素材有自己的编号；它属于哪个样品，记在链接表里。一个素材可以链接多个样品。
- **K6 取消链接不等于删除。** 取消链接只删掉链接表里那一行，素材本身和它的其他链接不动。
- **K7 原始文件不改写。** Source 的内容登记后不被修改。从原始文件整理成 Dataset 时只做格式整理和有依据的单位换算，不做平滑、扣背景、拟合等科学处理；这些属于分析，产出是 Result 或 Plot。
- **K8 Sample Result 只有当前值。** Library 级 Result Definition 先规定用户需要哪些科研数值、单位和可选限定文字（`@300 K`、`@30° device` 等），Sample 中按 `definitionID` 保存一份被确认的当前值；手填与 Workbench 只是两种写入入口。修改经用户一次明确确认后覆盖旧值；未确认不生效，不保留日常值历史。Definition 未填写时只是空槽位，不制造零值。
- **K9 人工最终决定。** Workbench 计算输出不能自动改 Sample Result；用户明确指定目标 Definition、看到提示并确认后才可写入。用户可人工填写或覆盖同一槽位。Definition 的限定文字不是每次测量的来源证明，系统可提示不匹配，但不替人作最终科研判断。已有 Source、Dataset、Plot、Sidecar 不被反向改写。
- **K10 仅 Live 计算成果随输入失效。** 对声明了依赖的 Live 分析产物（包括相应 Plot/派生计算 Result），Dataset、有效输入、计算方法等变化须标记过期并按正式提交边界保护；**用户确认保存的 Sample Result 是独立当前值，不自动清空、不自动重算、不因上游测量文件改变而静默覆盖。** 将来建立明确的持续依赖关系时必须另立消费者合同。
- **K11 快照不跟着变。** Snapshot 保存当时的输出和所用的输入值，之后不随任何修改而变。
- **K12 不知道就留空。** 归属、单位、通道含义不明确时保持"未知"，不按文件名、通道号或最相近的名字猜。
- **K13 损坏不等于不存在。** 文件读不出来、索引缺失时报错并停止，不当作空库继续写。

**两层 Result 的物理组织（任务 4 起）：** Library 保存一份共用 Result Definition Catalog（拟放 `_spinlab/result_definitions.json`）；各 Sample 的正式 `sample.json` 新增可选的 `results` 当前值映射。一个 Definition 可以在许多 Sample 显示，但只有填值的 Sample 才有记录。Definition 稳定身份不由显示名/限定文字计算；已被使用的定义不能无提示改变科学含义或被删除。Result Definition 的限定文字不要求携带完整 Measurement Condition、Sidecar 或 Analysis Configuration。测量的真实固定条件与扫描轴仍由 Source/Dataset 的 Sidecar 体系保存；分析配置在 Workbench/已保存分析产物中管理。当前数值不在 SQLite、`numericTags`、`measurement_data.json` 中再存一套；Storage v2/任务 5 不得为其新增第二权威。

**Dataset 同 ID 更正的安全底线（任务 5 才实现）：** 只允许同一 Source 的同一信号做忠实解析或有依据的解释更正；更正启动时记下该 Dataset 的当前内容标记，正式提交前再次核对。若期间已被其他操作更新，则拒绝过期提交并报告冲突，不让晚完成的旧任务覆盖新确认的内容。同一操作的重复提交不生效两次；更新成功后按 K10 使下游结果过期。单写者保证提交串行，但不能代替过期校验。具体实现由任务 5 的设计决定，不要求现在建立历史版本库或跨进程协调日志。

**Live / Snapshot 提交的安全底线（首次消费者才实现）：** 此段只针对存在真实依赖的 Live 计算产物，不对任务 4 的 Sample 当前 Result 格子强制自动失效。后台计算只产生候选输出；把已有 Live 分析 Result/Plot 发布为 `current` 时，须在**同一不可交错的正式提交边界**内核对全部直接及传递依赖的当前标记、方法/配置/归属和该 Live 对象自身的定义/状态标记，并完成输出发布与状态更新。输入变更及其下游失效必须与发布共享这一串行提交次序；不能先检查再放开保护、随后另行标记 `current`。若标记或绑定已变，拒绝旧输出、保持过期状态；即便值从 A→B→A 也不能把旧任务重新判为有效。用户主动保存 Snapshot 时，同样须在不可交错的提交确认点核实所固定的 Live 输出、完整依赖及归属，并且只在必要的不可变内容可读、固定成功后宣告 `saved`；有并发变动则拒绝/重试，不产生伪有效快照。可用单写者内的串行临界区/本地事务满足，具体存储与恢复策略留给任务 6 或首次 Snapshot 消费者设计；不要求任务 1–5 提前实现跨进程 CAS 或新日志系统。

## 存在哪里

### 当前 V1（仍然有效的实际路径）

- 样品的正式记录仍在现有 Batch 抽屉下：`batches/.../<batch>/samples/<sampleKey>/sample.json`；原始测量文件与 `measurement_sets.json` 等也按旧位置处理。这里的 `...` 包括已有的批次前缀目录兼容布局。
- 现有根目录 `samples/<sampleKey>/_spinlab/`、`samples/<sampleKey>/charts/` 保存分析索引与产物；多样品图仍可能位于 `_spinlab/multi-sample/charts/`。**这不是第二个 Sample 实体**，只是旧的产物目录。
- 现有旧库不搬家、不批量改写。仅保留已授权的旧 Sample UID 原位补发例外（先预演、备份、校验）；不动原始文件、测量和旧图。
- 任务 4 起：Result Definition Catalog 保存在 Library 下单一 JSON 配置（计划路径 `_spinlab/result_definitions.json`），Sample 当前 Result 数值保存在该 Sample 的 `sample.json`；旧库数据不搬家。任务 5 仅开始登记 Source/Dataset 等资产与关联到 SQLite，不复制 Result Definition/当前值；大文件仍存文件系统。

### Storage v2 目标（待任务 10、5、11 分阶段实现；不是现行写入规则）

```text
Library/
├── records/                            # V2 新增顶层；避开 V1 已知路径冲突（不等于旧版安全）
│   ├── batches/<batchID>/batch.json    # Batch 共享信息
│   └── samples/<sampleUID>/sample.json # 唯一 Sample 正式记录
├── storage/<assetID>/...              # 有文件内容的 Source/Dataset/Plot/Attachment 等
└── _spinlab/library.sqlite            # Asset 登记、关系、位置与校验
```

> V2 记录树放在新的顶层 `records/` 下，不复用 V1 已占用的 `batches/` 与 `samples/` 名字，避免已知路径冲突。**这不能保证旧版 App 安全**：旧版打开 Library 可能创建 `index/`、`batches/` 并重建索引。按用户的单人、所有电脑受控升级约定，**不支持旧版 SpinLab 对 V2 Library 降级写入**，任务 10 不建设旧版互操作/防写兼容层，也不以旧版写入 V2 为验收；必须保证当前新版继续正确读写既有 V1 Library，并对 V2 版式异常、重复正式记录与混合状态 fail-closed。详细路线见 [`brief-10`](brief-10-storage-v2.md)。

- **科研组织不变**：UI 按 Batch → Sample 展示。Batch 仍是一次 PLD 生长的分组信息，`sample.json` 的 `batchId` 表示其归属；`records/` 下磁盘不再以 Batch 目录嵌套 Sample。保留 `batch.json` 不意味着引入新的独立 Batch 机器身份。
- **权威只有一处**：一个 Sample 只有一个可写的正式 `sample.json`；Batch 下有哪些 Sample 由归属查询得出，不把 `batch.json.sampleKeys` 当成第二套独立权威。Growth Parameters 在 V2 的 `records/batches/<batchID>/batch.json` 持有唯一科研权威；同一生长数值不在 Sample 中独立维护。任务 10 须盘点并改造 Registry 解析/同步、Sample 新建/编辑、展示/索引与 `numericTags` 读写点，保留 V1 兼容；任务 11 才准对真实旧库逐项校验冲突和迁移，不借目录切换擅自改数据。Result Definition Catalog/各 Sample Result Value 则各有唯一权威，任务 10/11 保留其身份、数值和未填写状态，不在 SQLite 复制当前值。
- **资产不属于某个文件夹**：Source、Dataset、Plot 等通过稳定 Asset ID 定位；Sample—Asset 关联（可多对多）及必要派生关系由 SQLite 集中管理，不在每个 `sample.json` 或 `assets.json` 再写一份关联表。Unlink 不删除素材；删除 Sample 不得沿目录递归误删共享资产（彻底删除的 V2 规则见下）。
- **路径不是身份**：移动、改名或更正 Batch 归属不改变 Sample/Asset ID。小型 Result 等没有独立文件时不必为其创建空的 `storage/` 子目录；此树表达目标边界，不规定所有对象都必须有物理文件。
- **安全转换**：V1/V2 使用明确、可验证的布局版本和统一路径解析；不能靠“发现某文件夹存在”猜测写入位置，不能对同一 Sample 在两处并行写入。缺失、损坏、冲突或迁移中断一律 fail-closed，不把未知当空库。任务 10 只在测试 Library 验证 V2 路由及**当前新版读取 V1 旧库**的兼容；任务 5 引入 SQLite 资产关联和新数据存储；任务 11 另行设计并授权生产旧库的备份、迁移、验证、切换与恢复。迁移前提：全部 Sample 都有合法且唯一的 `sampleUID`；仅历史样品需要校验旧 Key 映射（`legacySampleKey`，手工/手机创建的样品本来没有旧 key，可为空）。迁移后历史样品的目录名由旧 key 变为 `smp_` 编号，对照与 PR #220 的补发备份须保留到迁移验收完成。

### 彻底删除（V2 规则；V1 现行行为不变）

- **V1 现状**：废纸篓里的样品被彻底删除时，删除其 Batch 抽屉下的样品目录及根目录 `samples/<key>/` 产物目录；不碰 `_spinlab/multi-sample/charts/`。现行行为保持不变、不回退；跨样品引用的安全尚未完整验证（V1 没有共享资产关系，目前只确认本地库内单样品图未被多样品 manifest 同时列出）。
- **V2 只规定安全不变量，不冻结实现顺序：**
  1. 只删除确认“仅属于该样品、且没有任何其他有效引用”的资产。引用不止 Sample—Asset 关联，还包括其他 Dataset、Result、Plot、Snapshot 等的依赖；关联数为零不等于可删。
  2. 被其他样品或其他对象引用的资产一律保留（K6、K7）；不按目录整体删除，不删未登记文件，不顺手清理无关孤儿。
  3. 确认弹窗如实显示“将删除 N 个文件，另有 M 个仍被使用，会保留”。
  4. 任何中断后不得留下无法解释的状态，不当作空库继续（K13）。
- **任务 5 必须设计并验证**：完整的引用保护、删除提交和中断恢复机制（含崩溃注入测试）。具体的先后步骤与标记方式由任务 5 设计决定，此处不预设。
- **多样品图（现状与处理）**：V1 的 `_spinlab/multi-sample/charts/` 每张图的 manifest 记录原始数据的绝对路径，删除其中一个样品后图保留、路径失效。任务 5 起，多样品 Plot 按 K5 同时关联多个样品；其中一个样品被彻底删除后，Plot 保留并按 K10 标记“输入已变化/需要更新”，不再展示为当前结果。V1 阶段不增加机制。

## 使用上的前提

- 同一个 Library 同一时间只有一个 SpinLab 进程可写；第二个实例只读打开。
- 用户不绕过 SpinLab 手动改 Library 里的文件。
- 所有使用同一 Library 的电脑只运行当前兼容版本；Library 升级到 V2 后不使用旧版 App 修改它，不要求旧版降级写入兼容。不同于此，新版对 V1 旧库的兼容必须保留。
- 所有开发和测试都在单独的测试 Library 里进行，不碰真实数据。

## 现在不做

- 删除批次：保持禁用（不做批次级一键清空）。删除样品已在 v6.1.0（PR #219）开放：先进废纸篓，可恢复，在废纸篓里可永久删除。
- 旧数据迁移（旧样品文件夹、测量与出图记录不移动；未来须经任务 11 单独设计与授权）。旧样品补发 `smp_` 编号是 PR #220 放宽的唯一例外：应用内先预演、确认后备份再原位补写，不改文件夹。
- 手机同步（PR #220 放宽的另一个例外：手机样品拾取，UID 由提交 id 确定性生成、重复拉取不重复建样品；其余手机同步仍等后续）、批次改编号、独立的 Device / Measurement 类型：等第一个真正需要它的功能出现时再定。
