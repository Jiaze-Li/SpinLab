# SpinLab 执行包

这里是给 Agent 派任务时直接用的材料。旧的设计文档（D6-A、D6-B、G0、新数据库 v0.2）保留作参考，不再作为派任务的输入；两边说法不一致时以这里为准。

## 里面有什么

- [`SKELETON.md`](SKELETON.md)：数据骨架。一页，每次派任务都附上。
- `brief-N-*.md`：每个任务一份需求。写的是"我要什么、不要什么、怎么验收"，以及 Agent 需要知道的代码现状。

## 任务顺序

| 顺序 | 任务 | 需求 | 流程 | 前置 |
|---|---|---|---|---|
| 1 | 新建样品，编号永久不变 | [`brief-1`](brief-1-create-sample.md) | design → code | 无 |
| 2 | Registry 少一行不再删样品，删除暂时关闭 | [`brief-2`](brief-2-safety-guard.md) | code | 任务 1 已合并 |
| 3 | 同一个 Library 只允许一个 SpinLab 可写 | [`brief-3`](brief-3-single-writer.md) | code | 无 |
| 4 | 手填参数，确认后直接覆盖 | [`brief-4`](brief-4-parameters.md) | design → code | 任务 1 已合并 |
| 5 | AFM 文件入库成标准数据（引入链接表） | D6-B 的 T03 任务卡，去掉"开工门槛" | design → code | 任务 1 |
| 6 | AFM 处理与出图改读标准数据 | D6-B 的 T04 任务卡，同上 | design → code | 任务 5 |
| 7 | AFM 自动出图 | D6-B 的 T05 任务卡，同上 | design → code | 任务 6 |

任务 5 之后的需求在轮到它之前再写，写法照 `brief-1` 到 `brief-4`。

任务 2 排在任务 1 之后，是因为它的代码（PR #195）叠在任务 1 的分支上，直接搬到 `main` 会冲突。在任务 2 合并之前，同步 Registry 前先看预览里 removed 的数量，不是 0 就不要点应用。

## 原来的 G0–G5 去哪了

不再作为单独的关卡。每块基础由第一个需要它的任务带着做：

| 原关卡 | 现在 |
|---|---|
| G0 设计准备 | 由 `SKELETON.md` 和各任务的 design 模式替代 |
| G1 数据安全 | 任务 2、任务 3 |
| G2 样品编号 | 任务 1 |
| G3 手工记录 | 任务 4；照片和笔记之后另开 |
| G4 标准数据 | 任务 5 |
| G5 结果与自动执行 | 任务 6、任务 7 |

## 每个任务怎么走

**design → code 的任务：**

1. 让 Agent 读 `SKELETON.md` 和对应的 brief，核对 brief 里的"代码现状"。
2. Agent 以 `taskType: "design"` 调用 `reviewloop_begin`：brief 全文作为 `contractText`，`SKELETON.md` 里的 K1–K13 作为 `constraints`。Agent 起草合同，ReviewLoop 审。
3. 通过后你会收到最多五行的摘要和一份"假设"清单。**逐条读假设。** 有一条不符合你的实际情况，就打回。
4. 你确认后，Agent 以 `taskType: "code"` 开始实现，先核对 `design_ref`。
5. 推送后等评审机器人；通过后你按 brief 里的"我怎么验收"在测试 Library 里亲手走一遍；然后合并。

**只走 code 的任务：** 跳过第 2–4 步，brief 全文直接作为 `contractText`。

## 三条止损规则

- 合同超过两页，说明任务太大。停下来拆任务，不要继续加内容。
- design 审查三轮没过，停下来。缩小需求再来，不要补更多机制。
- 合同里出现 brief 和 `SKELETON.md` 都没提到的机制（锁、日志、重试、新的状态），要求 Agent 说明是哪条需求需要它；说不出来就删掉。

## 你要做的只有三件事

1. 派任务前读一遍 brief，不符合你想法的地方先改 brief。
2. design 通过后读假设清单。
3. 合并前按 brief 亲手验收。
