# s1 遗留：测试 fixture 跟不上 schema 改名 / canonical key 算法

权威设计：本 handoff 自身（s1 schema 大改的 fallout 清单）。s2 验收过程中发现并隔离，不属于 s2 范围。

## 背景

s1（5.1.5 会话 1，2026-04-25）做了「7 文件 canonical schema」迁移，其中：
- `Sources/SpinLabApp/config/filename_rules.json` → `Sources/SpinLabApp/config/filename_parse_rules.json`
- substrate canonical key 算法变更（具体改动见 s1 commit `100e4cd` / `5b10d0f`）

**未同步更新测试 fixture**。s1 + s2 期间测试 target 一直没跑（s2 验收时另有 4 个 suite 因 API 改动连编译都过不了——已在 commit `618a991` 用 `#if PORT_TESTS_TO_NEW_*_API` 隔离）。

s2 验收最后一步 `swift test` 才暴露这批 fixture 路径与算法假设的不一致。

## Jack 会看到什么

修复后：`swift test` 全绿（除已隔离的 4 个 suite 外）。无功能变化。

## 故障清单

### 1. fixture 硬编码旧 JSON 路径（4 处，纯改名）

| 文件 | 行号 | 错误 |
|---|---|---|
| `Tests/SpinLabAppTests/V210ImportAndParseTests.swift` | 449 | `appendingPathComponent("Sources/SpinLabApp/config/filename_rules.json")` |
| `Tests/SpinLabAppTests/V214RegistryRuleBookTests.swift` | 68 | 同上 |
| `Tests/SpinLabAppTests/V224RegistrySubstrateRuleBookTests.swift` | 40 | 同上 |
| `Tests/SpinLabAppTests/V225RulesConfigContractTests.swift` | 340 | 同上 |

> V214/V224/V225 当前已被 `#if PORT_TESTS_TO_NEW_*_API` 关掉，但等那批 API 修复后需要解锁；解锁前/后都要顺手把这条路径改对，不然立刻又炸。

修复：把 `filename_rules.json` 改成 `filename_parse_rules.json`。

### 2. V210ImportAndParseTests — 24 项失败

全部失败模式相同：
```
Error Domain=NSCocoaErrorDomain Code=260 "The file 'filename_rules.json' couldn't be opened because there is no such file."
```

根因：`loadBundledRuleSetForTests()`（V210ImportAndParseTests.swift:446）走旧路径。
修复：改路径即可（一行修复）。

### 3. V221DrawerMatchEngineTests — 4 项失败

断言形如 `descriptor.canonicalKey == "PN32|HF+b+o|STO|111"`，实际得到 `"PN32||STO|111"`（中间字段空了）。

根因：substrate canonical key 中的 treatment 段（`HF+b+o`）算法在 s1 重写后行为变了——可能是：
- treatment token 列表变了（s1 改了 sharedSubstrate.treatmentKeywords 字典结构）
- canonical key 拼接顺序变了
- 或 normalizedProcessingTokenForRules 处理路径变了

修复：先 grep `canonicalKey` / `normalizedProcessingTokenForRules` 看当前实现的预期值，然后把测试断言换成新的正确值（fixture 不动 substrate token 列表的话）。

### 4. V212RoutingDraftTests — 7 项失败

具体断言失败模式同 V221（依赖 canonicalKey 或 substrate normalization 输出）。先修 V221、确认 canonical key 公式后，V212 大概率自动匹配。

### 5. V223AppEnvironmentIntegrationTests — 4 项失败

样本失败：
- `appState.inbox.pendingImports.count → 0` 期望 1（import 路径全断；可能是 RuleLoader 失败级联到 import）
- `draft.workflowID → ""` 期望 `"AHE"`（workflow 解析失败）
- "Timed out waiting for condition"（异步 import 等待超时）

根因猜测：V223 是 **integration 测试**，会真的触发 RuleLoader → 走到测试 bundle 的 config 路径 → fixture 不全或路径不对，所有 import 走 fallback 0 条。

修复策略：先查清 V223 怎么 seed runtime config，确认 7 文件 fixture 是否齐全 + 路径对得上。

## 范围边界

**不动**：
- 任何 production 代码（`Sources/`）
- 任何 fixture JSON 内容（除非证明 algorithm 输出真的变了，需要重新生成 fixture）
- `#if PORT_TESTS_TO_NEW_*_API` 隔离的 4 个 suite（V214/V224/V225/V240）—— 那批要先把底层 API 形态稳定下来再单独开任务

**可动**：
- 测试文件里的硬编码路径字符串
- 测试断言的期望值（前提是确认是 algorithm 改动而非真 bug）
- 必要时新增 fixture seed helper

## 修复顺序

1. 先 V210（24 个失败，全是路径问题，一行修复 → 24 个红变绿，最大杠杆）
2. 再 V221（4 个失败，需要查 canonical key 当前实现确认期望值）
3. 再 V212（7 个失败，跟 V221 同源）
4. 最后 V223（4 个失败，integration 路径，最难诊断）

每一步独立 commit，方便回退。

## 风险

- 修期望值时千万别把真 bug 当成「algorithm 改动」改掉；遇到不确定的 case 先停，问 Jack（或对照 features.md / specs/02_DATA_RULES.md 的契约确认）
- V223 的 timeout 失败可能不是路径问题而是别的（async race / 测试 helper bug），不要预设是 fixture 不全

## 启动指令

```
读 docs/handoff/2026-04-26-s1-fixture-fallout-test-fixture-rename.md，按其中【修复顺序】1→4 推进。每步独立 commit。每跑 swift test 一次确认数字朝着 0 走，不要堆改动。第 2/3 步遇到不确定的期望值停下问 Jack，不要凭直觉猜。
```
