# v5.1.5 s9 — Schema 二次重塑实施摘要

**对应 handoff**：`docs/handoff/archive/2026-04-26-5.1.5-s8-schema-second-pass.md`
**完成日期**：2026-04-27
**执行**：Codex（C1/C2/C3b/C6）+ Claude（C3a/C4/C5/C7 bug fixes）

---

## 实施内容

### C1 — 数据模型层
- `FilenameRuleSet.ConditionDefinition`：删 `binding`，加 `unitPattern: String?` + `tokenMap: [MapRule]?`
- `FilenameRuleSet.SharedSubstrateRules` 整 struct 替换为 `SubstrateConfig` + `MaterialDefinition` + `TreatmentDefinition` + `OrientationConfig` 4 个 row-oriented struct
- `MatchSpec`：`value: String? + values: [String]?` → `matchValues: [String]`（backward-compat Decodable）
- `RuleCanonicalizer`：退役 `normalizeConditionDefinitionBindings`；保留 `migrateUserRuleJSONToCanonical` 作 v1→v2 转换器

### C2 — RulesBootstrapper 迁移
- `migrateRuntimeRulesToV2IfNeeded()`：tmp + verify + atomic replace + backup + migration_state
- 幂等键：`migration_state.rules_schema_version >= 2`
- 脏数据处理：kind/binding 不一致记 warning，按 kind 优先

### C3a — Import 消费侧切换
- `FileRoutingSemanticRules`、`RegistrySubstrateRuleBook`、`SpinLabRuleProvider` 切换至 row-oriented 数据

### C3b — Library 消费侧切换
- `LibraryRegistryParser`、`LibrarySampleEditService` 切换至 row-oriented

### C4 — RulesPanel 模型层
- `RulesManagementStore` Draft types 改 v2 schema
- 校验：unit_suffix 互斥 tokenMap；token_map 互斥 unitPattern；substrate row ID 唯一性

### C5 — RulesPanel UI
- `MeasuringConditionSection`：inline unitPattern / tokenMap 编辑器
- `SampleIdentificationSection`：3 row-oriented 编辑器（materials / treatments / orientations）

### C6 — 命名扫尾
- `MatchSpec.value/values → matchValues` 全仓 grep 修（13 文件）
- `library_import_rules` 重复 substrate 段清理（`substrateMaterialTokens` / `substrateProcessingKeywords`）
- `conditionFieldIDs→conditionFieldIds` 评估后放弃（命中 >30 处，移 5.1.6）

### C7 — 测试 + 收尾
- 修复 5 个测试文件（v1 API → v2）：`V515RulesPanelSaveValidationTests`、`V515RulesPanelCrossSectionTests`、`V515RulesPanelStoreTests`、`V515RulesSaveImmediateEffectTests`、`V515RulesSyncStartupTests`、`V515SharedSubstrateTests`
- 新增 `V515RulesBootstrapperMigrationTests`（5 个迁移幂等单测）
- 最终：**84/84 V515 green + 27/27 V210 green**

---

## 关键设计决策

| 决策 | 采纳方案 | 理由 |
|---|---|---|
| `substrate.shared` 容器 | 整删 | 9 字段重组后 shared 名字失去语义 |
| orientations 结构 | row-oriented（rows[]） | 与 materials/treatments 一致 |
| 兼容读取窗口 | 不留 | 单用户应用，迁移完即只读 v2 |
| `conditionFieldIDs` 重命名 | 本期放弃 | grep 命中 >30 处，超 2h 预算 |
| MatchSpec backward-compat | 自定义 Decodable + 显式 Encodable | Swift 不合成 Encodable 当有自定义 init(from:) |

---

## 测试覆盖

- V515 RulesBootstrapper Migration：5 tests（v1→v2 / 幂等 / 已v2短路 / 脏数据警告 / backup JSON合法）
- V515 Shared Substrate：4 tests（duplicate material/orientation ID / valid save / invalid regex）
- V515 RulesPanel Save Validation：12 tests（各 section 校验路径）
- V515 RulesPanel Cross-Section：4 tests（workflow↔measuringCondition 跨 section 校验）
- V515 RulesPanel Store：9 tests（load / dirty / discard / reload / save / conflict / override）
- V515 Rules Save Immediate Effect (R1)：4 tests
- V515 RulesSyncStartup：12 tests
- V515 RulesSyncEngine：20 tests
