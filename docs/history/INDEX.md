# History Index

> 永久全量。按完成时间倒序。每条事件归档时同步追加（§9.c 第 3 步内子动作）。
>
> 替代原 `docs/README.md`「Development Log」表 + 原 `docs/handoff/README.md`「已归档」表两份冗余索引。

| 完成日 | 版本 | 一句话 | history 文件 | handoff archive | commits |
|---|---|---|---|---|---|
| 2026-04-27 | 5.7.1 | TASK_BOARD 引入 + 文档治理重构：新建 TASK_BOARD + history/INDEX，退役 handoff/README + TECH_DEBT_BACKLOG，改 docs/README.md + 项目 CLAUDE.md + 全局 workflow.md | [v571_task_board.md](v571_task_board.md) | [archive/2026-04-26-5.7.1-task-board-introduction.md](../handoff/archive/2026-04-26-5.7.1-task-board-introduction.md) | 9f5dc7d (项目) + dotfiles 719bb81 + 40c4fec |
| 2026-04-27 | 5.1.5-s9 | ConditionDefinition inline + SubstrateConfig row-oriented + MatchSpec.matchValues 全仓统一 + RulesBootstrapper v1→v2 迁移（atomic + state + backup）；5 迁移幂等单测；84/84 V515 green + 27/27 V210 green | — | [archive/2026-04-26-5.1.5-s8-schema-second-pass.md](../handoff/archive/2026-04-26-5.1.5-s8-schema-second-pass.md) | C1–C7 |
| 2026-04-26 | 5.1.5-s7 | rules tail cleanup：WorkflowDefinitionStore + WorkflowRegistryRetirementService + parentID 兼容删 + RulesBootstrapper 替换 RulesMigration + WorkflowRegistryView 只读重写；11 tests（79/79 V515 green）| — | [archive/2026-04-26-5.1.5-s7-rules-tail-cleanup.md](../handoff/archive/2026-04-26-5.1.5-s7-rules-tail-cleanup.md) | 5 commit (08c7f8a–f7939c4) |
| 2026-04-26 | 5.1.5-s6 | 自动同步引擎：RepositoryPointer + RulesSyncEngine + degraded UI + 32 tests；68/68 V515 green | [v515_s6_auto_sync_engine.md](v515_s6_auto_sync_engine.md) | [archive/2026-04-26-5.1.5-s6-auto-sync-engine.md](../handoff/archive/2026-04-26-5.1.5-s6-auto-sync-engine.md) | 99514e2 + 4a586fe |
| 2026-04-26 | 5.1.5-s5 | 规则面板重写：RulesManagementStore + 5 新 section + WorkflowMatchRuleEditor + 36 tests；R1 硬门禁满足；旧 5 section 文件全删；swift build clean | [v515_s5_rules_panel_rewrite.md](v515_s5_rules_panel_rewrite.md) | [archive/2026-04-26-5.1.5-s5-rules-panel-rewrite.md](../handoff/archive/2026-04-26-5.1.5-s5-rules-panel-rewrite.md) | ea09161 |
| 2026-04-26 | 5.1.5-s4 | 5 本子 schema 落地 + RuleLoader/RulesMigration 重写 + WorkflowIDAllocator/parentID/rotationHintRules 退役 + 旧 bundle 文件删除 + V210 fixture 更新；swift build clean + 测试全绿 | [v515_s4_schema_migration.md](v515_s4_schema_migration.md) | — (handoff 文件位置不可考) | — |
| 2026-04-26 | 5.1.5-s3 | s3 双盲对抗 Round 2：盘点 + 5 本子分类设计稿 + 退役调用点全清单 + 新 schema 草案；C1-C6 commit 链 | — | [archive/2026-04-26-5.1.5-s3-rules-redesign.md](../handoff/archive/2026-04-26-5.1.5-s3-rules-redesign.md) | 8df3ee7 + a9ebf19 + f527d17 + 362025b + 1a62ed8 + 747b7e4 |
| 2026-04-26 | 5.1.5-s2 | 规则面板搭骨架：6 分区 NavigationSplitView + 4 编辑分区 + Inbox 入口 + MatchRuleEditor/RegexField；swift build clean | — | [archive/2026-04-26-5.1.5-s2-rules-panel.md](../handoff/archive/2026-04-26-5.1.5-s2-rules-panel.md) | 494ab17 + 3fb92ac + a8cf29a + e583534 |
| 2026-04-26 | s1-fixture-fallout | 测试 fixture 改名收尾：路径改名 + V515 隔离 + V210/V223/V214/V224/V225/V240 完整修复；swift test 全绿 | — | [archive/2026-04-26-s1-fixture-fallout-test-fixture-rename.md](../handoff/archive/2026-04-26-s1-fixture-fallout-test-fixture-rename.md) | 80959a1 + a6edeca + 2ee4d6c + 10c7d47 |
| 2026-04-25 | 5.1.5-s1 | 规则统一：旧规则 UI 三处删除 + 7 文件 schema 落地 + 一次性迁移器 + sync 脚本删除；swift build clean | — | [archive/2026-04-25-5.1.5-s1-rules-unification.md](../handoff/archive/2026-04-25-5.1.5-s1-rules-unification.md) | 63c891a→5b10d0f |
| — | 5.5.0 | Cross-Area UI Unification（字体可读性 / 折叠区块 / 字体梯度 / 间距常量 / 按钮风格 6 项）| [v550_ui_unification.md](v550_ui_unification.md) | — | — |
| 2026-04-26 | 5.3.5 | Point Label Font Size + Visibility Toggle + Copy PNG Scale Menu | [v535_point_label_controls.md](v535_point_label_controls.md) | [archive/2026-04-26-5.3.5-point-label-controls.md](../handoff/archive/2026-04-26-5.3.5-point-label-controls.md) | — |
| — | 5.3.4 | Legend Dimension Auto-Inference + Visual Consistency（resolver + payload + 16 tests）| [v534_legend_dimension_resolver.md](v534_legend_dimension_resolver.md) | — | — |
| — | 5.3.3 | Multi-Tab Render State Manager（TabRenderState + TabRenderOutput + 3ω/XY/AHE 三 store 状态重组）| [v5.3.3_multi_tab_render_manager.md](v5.3.3_multi_tab_render_manager.md) | — | — |
| — | 5.3.2 | Plot Render Pipeline unification（WorkbenchRenderPipeline 三 workflow 共用）| [v5.3.2_render_pipeline.md](v5.3.2_render_pipeline.md) | — | — |
| — | 5.3.1 | Plot Shell capability expansion（绘图模式 / 字号 / tick 密度 / 辅助线 / Copy PNG）| [v5.3.1_plot_shell.md](v5.3.1_plot_shell.md) | — | — |
| — | 5.0.0 | Knowledge accumulation system setup（philosophy / features / known_issues / devlog 系统化）| [v5.0.0_doc_system.md](v5.0.0_doc_system.md) | — | — |

**说明**：
- 「完成日」按 handoff archive 文件名日期 / commit 日；纯 history 文件无明确归档日的填 `—` 占位
- 「history 文件」/「handoff archive」缺一是因为：(a) 早期 v5.0/v5.3.x 完成时未走 handoff 流程，无 archive；(b) 5.1.5-s3/s2/s1/s1-fixture 当时未生成独立 history 文件，设计思路集中在 ROADMAP 5.1.5 段；(c) s4 handoff 文件位置不可考
