# Handoff & Tmp Lifecycle

跨会话任务传递的项目侧落地。生命周期权威定义在 `~/.claude/docs/workflow.md §9`，本文件给 SpinLab 的具体路径约定 + 索引 + tmp 清理规则。

> **跟 ROADMAP / history 的边界**：handoff = "**接手怎么照做**"（临时执行包，归档后被 history 引用）。**不**承担"要做什么"（那是 ROADMAP）和"做了什么 + 为什么"（那是 history）。三类分工详见 `docs/README.md` 顶部「三类文档分工」表。

## 三态生命周期

| 状态 | 位置 | git | 说明 |
|---|---|---|---|
| **草稿** | `tmp/<任意名>.md` | ignored | 起草中的 handoff、临时 dump、一次性 scratch。可能不完整、可能废弃 |
| **待消费** | `docs/handoff/<YYYY-MM-DD-短主题>.md` | tracked | 已完成的 handoff，等接手会话拾取。**必须**在下方"待消费索引"登记 |
| **已归档** | `docs/handoff/archive/<YYYY-MM-DD-短主题>.md` | tracked | 已被消费完毕的 handoff，保留作历史 |

### 状态迁移

- **草稿 → 待消费**：handoff 草稿完整可消费时，`mv tmp/* docs/handoff/<YYYY-MM-DD-topic>.md`，同时在本文件「待消费」段加一行
- **待消费 → 已归档**：接手会话完成任务后，`git mv docs/handoff/<file> docs/handoff/archive/`，同时把「待消费」那行剪到「已归档」段

## tmp/ 清理约定

`tmp/` 是 ephemeral scratch 区，**不是长期存放点**。

**每次会话开始**（项目级 session protocol）：

```bash
ls tmp/ 2>/dev/null
```

对每个残留文件三选一：

- **还在用** → 留着，告诉 Jack 是什么、为什么还要
- **可升级为待消费 handoff** → `mv` 到 `docs/handoff/` 并登记
- **已废弃** → `rm`（不归档——草稿没人消费过，没保留价值）

超过 14 天没动的 tmp 文件，**默认提示 Jack 是否删除**。

## 待消费

| 日期 | Handoff | 一句话目标 |
|---|---|---|
| 2026-04-25 | [`2026-04-25-rules-architecture-cleanup.md`](./2026-04-25-rules-architecture-cleanup.md) | 规则管理架构清理（v5.1.5）：6 类规则统一为单文件 + UI 全可见 + bundle/runtime 字节对齐 |

## 已归档

| 日期 | Handoff | 完成会话 |
|---|---|---|
| _（暂无）_ | | |
