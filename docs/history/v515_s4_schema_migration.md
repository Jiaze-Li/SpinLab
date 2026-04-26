# v5.1.5 s4 — 5-book v3 schema 迁移：实施摘要

**设计思路权威来源**：`docs/V5_ROADMAP.md` §5.1.5「二次规划」段（5.1.5 完成后迁此）

---

## 实施摘要

### Commits

| Commit | 内容 |
|---|---|
| 8df3ee7 | s4-C1: 新 5 本子 schema 文件 + RulesConfigPaths 新路径 |
| 362025b | s4-C4a/C4b: WorkflowIDAllocator 整文件退役 + parentID 向后兼容 decode |
| 1a62ed8 | s4-C5: rotationHintRules 退役 → FilenameRuleParser 硬编码 |
| a9ebf19 | s4-C2: RuleLoader 5 文件装配 + compositeHash + fail-fast D11 |
| f527d17 | s4-C3: RulesMigration v2→v3 + parentID strip + 失败回滚 D5 |
| 747b7e4 | s4-C6: 旧 bundle 文件删除 + V210 fixture 更新 |

### 验收口径（全通过）

- swift build clean ✓
- D7 displayLabels：有消费方（ConditionFieldCatalog + 旧面板 UI）→ 字段保留 ✓
- D11 缺文件 fail-fast：RuleLoader 任一本子缺失即 throw + warning ✓
- D13 单字段权威：workflow.json 无顶层 measurementNameRules 字段 ✓
- WorkflowIDAllocator 零调用方 ✓
- V210 全套（32 tests）+ V515 全套（6 tests）全绿 ✓

### 与设计思路的偏差

- **RulesMigration.assembleNewSchema**：设计稿要求"读旧 v2 文件 → 转写 v3"，实施改为"从 bundle 复制新文件 + 从 workflow_registry.json 补充 conditionFieldIDs"。等效：旧 v2 文件内容与 bundle 默认值一致，用户对这些文件无自定义能力。
- **测试覆盖**：§9.1 启动验证最小集中 D5 回滚、D11 缺文件、D13 单字段权威已通过代码审查和单元测试间接覆盖；runtime 文件手动验证项留 s5/s6 真机走查时补完。

### 实际工作量

约 6–8 h（含 s3 设计稿 4–6 h + s4 实施 6–8 h），跨 2 个会话完成。
