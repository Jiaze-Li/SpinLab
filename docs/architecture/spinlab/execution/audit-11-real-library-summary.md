# Task 11 审计 A：真实 Library 数据可再生性（脱敏汇总）

对应 [design-11](design-11-v2-migration-readiness.md)。本文只含聚合结论：不含样品 ID、批次名、原始数值和用户路径。完整报告保留在本机，不进入仓库。审计为只读（Library 与应用支持目录前后快照 SHA-256 一致，共 9799 个条目；全程无网络、无写入）。

## 事实概况

- 真实库为 V1 布局，无布局版本标记，无任何 V2 数据。约 4500 个文件、约 100 MB。
- Source 约 1390 个（lvm 约 920、dat 约 400、ibw 约 65、txt 4），约 56 MB。sidecar 与 Source 一一对应，无孤儿、无缺失，均为 version 2。
- sidecar 记录的原始外部路径约 79% 已不存在，库内副本基本是唯一副本。所有记录均无内容哈希，无法证明导入后未被改动。
- 测量条件（温度、电流、角度等）只存在于文件名中。重解析：条件与 substrate 1390/1390 一致，测量时间戳全部可重算一致。
- workflow 自动分类约 97% 一致；差异来自规则版本演进（约 40 个 ibw 在旧规则落入 General，现规则归 AFM；4 个手工改派现规则已可自动识别）。
- 样品归属约 91% 可由文件名/文件夹推出，其余是导入时的用户路由，须按 sampleKey 与物理位置原样迁移。
- 重复内容约 86 组，其中约 85 组是多通道文件被复制进每个归属样品。

## 分类（A 不可替代必迁 / B 可从 Source+规则再生 / C 可重新分析 / D 缓存可弃 / E 不明）

| 信息 | 类 | 规模 | 说明 |
|---|---|---|---|
| Source 原始文件及文件名、mtime | A | ~1390 | 条件只在文件名；多数原路径已无 |
| 样品归属（sampleKey+物理位置） | A | ~1390 | 约 9% 不可推出 |
| Registry xlsx（外部源已不存在） | A | 7 sheet，~370 登记 | 含库中尚无 Batch 的登记行 |
| 规则书（位于 Library 之外） | A | 6 文件+备份 | B 类再生依赖它 |
| 原生创建的 Batch/Sample、样品永久身份（总数）、软删状态 | A | ~9 Batch / ~17 Sample / ~360 UID / 2 软删 | 随机/手写，不可再生 |
| 条件手工覆盖 | A | 63 条 | 约 94% 与当前规则输出相同，体量小，原样保留 |
| 真正的 workflow 改派 | A | 4（共 195 条 override，大多为无意义的 manual 标记） | |
| 数值手工修正、Sample Result 及定义 | A | 3 / 1 值+2 定义 | |
| measurement_sets | A | 84，约 6 个非 device 分组 | 其余可重建 |
| 待确认导入队列、仅存于 sidecar 的回退时间戳 | A（过渡） | 38 / 32 | |
| sidecar 条件/substrate/时间戳/来源引用 | B | 1390 | 重算一致 |
| Sample/Batch 元数据、数值标签 | B（来源 Registry） | 346 | 与 xlsx 100% 一致 |
| Plot 图片与 manifest、measurement_data 指标、Analysis Pack | C | ~190 / ~200 / ~380 / 23 | 其中 14 张图已丢 PNG、5 个 Pack 引用悬空；指标数值未做重算验证 |
| 索引与投影、回填前备份、编辑历史、日志、系统垃圾 | D | | 可重建或丢弃 |
| 导入审计日志 | D/E | ~1000 | 约 3/4 Source 的路由证据，建议只读归档 |
| 旧占位归档记录、项目分组 | E | 6 / 2 | 疑遗留 |

代码支持但真实库未使用：Sample 备注（0）、sidecar v1（0）、来源 ref 的 fallback/migration 标记（0）。AFM 与 MR 无图或 Pack。仍在真实使用：手工条件覆盖、workflow 改派、measurement_sets、Result 赋值、Hc 手工修正、Trash、原生创建。

## 最小必迁清单

1. 全部 Source 原样，保留文件名与 mtime。
2. Registry xlsx 与规则书。
3. 样品/批次身份、原生创建字段、软删状态及 Source→样品归属映射。
4. 用户手写决定：条件覆盖、真实 workflow 改派、数值手工修正、Result 及定义、measurement_sets。
5. 无 mtime 可依赖的时间戳、待确认导入队列。
6. 审计日志、原始路径、旧占位记录：只读归档。

## 可省略的旧兼容机制

sidecar v1→v2 解码；旧 fallback/migration 来源标记；缺 sampleKey/时间戳的向后兼容；旧占位归档读取；`workflowSource=manual` 无意义标记；索引/投影兼容读取（重建即可）；按绝对路径解析 Source；工作流目录大小写差异与 General 兜底桶。

## 需特别设计

- 样品键含 `/` 与 `|`，在全局树里会变成嵌套目录。
- 多通道同名文件的多归属（与 Audit B 的 D-B1 同一问题；真实库约 85 组，不是个例）。

## 未确认

指标数值是否可重算一致；同批多变体归属可恢复比例；导入后 Source 是否被改动（无哈希基线）；用户是否另有原始数据备份；待确认导入的外部原件是否保留；外部笔记库/网页库是否依赖库路径。

## 需要用户/Reviewer 决定（已在 [design-11](design-11-v2-migration-readiness.md) §5 处置）

1. Plot/Pack：只读归档，还是只迁 config 并在 V2 重算（建议后者的成本更低，但依赖公共能力先就绪）。
2. 多通道同名文件：每个样品一份物理副本，还是一份内容多处引用。
3. General 里的 ibw：迁移时是否按现规则重分类为 AFM。
