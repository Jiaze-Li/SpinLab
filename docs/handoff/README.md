# Handoff & Tmp Lifecycle

> 规则单一真相：`~/.claude/docs/workflow.md §9`（生命周期 + 内容约束 + 状态迁移 + tmp 清理 + **文件命名规范**）。本文件只给项目侧索引（待消费 / 已归档表）+ 执行分工表样板。
>
> 文件命名（含多会话拆分 `s<编号>` 编号约定）权威定义在 `workflow.md §9.a`，本项目不做覆盖，按那份执行。SpinLab v5.1.5 是首批使用多会话命名的 ROADMAP 条目（s1–s4）。

## 执行分工表样板（项目示例）

```markdown
## 执行分工
| 任务 | 负责 AI | 依赖 | 可否并行 | 备注 |
|---|---|---|---|---|
| Commit 1: bundle 主文件合并 | Claude | — | 否（先做） | 数据层，独立可逆 |
| Commit 2: 启动迁移代码 + 测试 | Codex | C1 完成 | 是（与 C3a 并行） | 后端逻辑 |
| Commit 3a: 删 UI 入口 | Claude | C1 完成 | 是 | UI 层 |
| Commit 3b: 删后端分文件代码 | Codex | C2 完成 | 否 | 后端清理 |
```

## tmp/ 残留 session protocol（项目级）

每次会话开始 `ls tmp/`，对每个残留文件三选一：

- **还在用**（当前对抗期内）→ 留着，告诉 Jack 是什么、为什么还要
- **对抗已收敛但 handoff 未落盘** → `mv` 到 `docs/handoff/` 并登记
- **已废弃 / handoff 已落盘** → `rm`（草稿无保留价值）

超过 14 天没动的 tmp 文件，**默认提示 Jack 是否删除**。

## 待消费

（无）

## 已归档

| 日期 | Handoff | 完成会话 | 验收摘要 |
|---|---|---|---|
| 2026-04-26 | [2026-04-26-s1-fixture-fallout-test-fixture-rename.md](archive/2026-04-26-s1-fixture-fallout-test-fixture-rename.md) | 2026-04-26 B | C1 80959a1 路径改名；C2 a6edeca V515 隔离；C3 2ee4d6c V210+RuleLoader 完整修复；C4 10c7d47 V223 bundle 隔离+120s 超时；swift test 全绿（V214/V224/V225/V240 按计划隔离） |
| 2026-04-26 | [2026-04-26-5.1.5-s2-rules-panel.md](archive/2026-04-26-5.1.5-s2-rules-panel.md) | 2026-04-26 | C0 494ab17；C1 3fb92ac；C2+C3+C5 a8cf29a；C4 e583534；6 分区 NavigationSplitView + 4 编辑分区 + Inbox 入口 + MatchRuleEditor/RegexField；swift build clean |
| 2026-04-25 | [2026-04-25-5.1.5-s1-rules-unification.md](archive/2026-04-25-5.1.5-s1-rules-unification.md) | 2026-04-25 | C1 63c891a→5b10d0f；旧规则 UI 三处删除 + 7 文件 schema 落地 + 一次性迁移器 + sync 脚本删除；swift build clean |
