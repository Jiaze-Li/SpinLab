# 5.1.5 s10 — Sample Identification 面板二次简化

> 实施完成：2026-04-27
> 对应 handoff：[archive/2026-04-27-5.1.5-s10-substrate-redesign.md](../handoff/archive/2026-04-27-5.1.5-s10-substrate-redesign.md)
> Commits：02abdfe（C1+C3+C4）、2523f20（C2）

---

## 实施摘要

v4 substrate schema 全量落地（SubstrateEntry 统一三表、batchPrefixes 替换正则 patterns、origin treatment 检测脱耦、v3→v4 bootstrapper 迁移）+ Sample Identification UI 完整重写。117/117 V515 + 18/18 V221 全绿。

---

## 设计思路

### 动机

s9 落地后 Sample Identification 面板仍过度工程化：Substrate Tag Rules 和 Substrate Configuration 干同一件事、id/token/alias 三字段是同一概念拆散、equalsAny/containsAny 等五种匹配类型用户看不懂、`^(PN|PT|SL)\d+$` / `\d{3}` 正则暴露给非技术用户。s10 一次性清掉所有冗余概念。

### 核心决策

**v4 Schema**：`SubstrateEntry {displayName, matches: [{type: equals|contains, value}]}` 统一 materials/treatments/orientations 三类配置。displayName 有隐式 equals 自匹配（compile 阶段注入），不需要在 matches 里重复列。matches OR 关系，token-scope。

**batchPrefixes**：plain text prefix 列表（如 ["PN", "PT", "SL"]），替换 `sampleId.patterns` 正则。用户视角看不到 `^(PN|PT)\d+$`。

**"b" 和 "baked" 分离**：保留独立 Treatments/b 行（equals "b"）+ Treatments/baked（contains "bake"）。防 Library 库存里旧 "b" tag 漂移。

**Origin treatment 脱耦**：compile 阶段检测 `normalize(displayName) == "o"` 或任一 match value 归一化后为 "o"，存入 `compiled.originTreatmentDisplayNames`。不再硬编码 treatment.id == "o"。

**复合 token 拆 tag（接受的行为变化）**：STO111 同时命中 Materials/STO（contains "STO111"）和 Orientations/111（contains "STO111"），产出 `["STO", "111"]` 而非旧的 `["STO 111"]`。已在设计纪要明确接受。

**v3→v4 迁移规则**：
- materials: tokens + aliases → equals matches
- treatments: standaloneTokens → equals，containsTokens + keywords → contains
- orientations: rows 展开，aliases → equals（displayName 自身跳过）；drop orientations.pattern + warning
- substrateTagRules: 全量丢弃 + per-rule warning
- sampleId.patterns: 识别 `^(PREFIX)\d+$` 形态提取 batchPrefixes；非标格式 warn + 丢弃
- migration_state gate: state >= 4 → skip

**否决方案（不要后续 agent 推翻）**：
- ❌ 只保留 Substrate Tag Rules 一张大映射表 —— 丢分类信息，routing 多衬底消歧依赖材料/方向区分
- ❌ 只删 UI 不删机制 —— 半成品双源
- ❌ 保留 equalsAny/containsAny/regex —— 多条件 OR + 两类型已覆盖；regex shipped 0 处使用
- ❌ 保留 scope 选项 —— shipped 0 处使用 joined；用户看不懂

### 13 条旧 substrateTagRules 去向

| 旧 rule | 新表 / 行 / match |
|---|---|
| HF | Treatments/HF + contains "hf" |
| BAKE/BAKED | Treatments/baked + contains "bake" |
| ORIGIN/ORIGINAL | Treatments/o + contains "origin" / "original" |
| STO111 → "STO 111" | Materials/STO contains "STO111" + Orientations/111 contains "STO111"（接受拆为双 tag） |
| STO001 → "STO 001" | 同上 |
| STO/NGO/111/001/o | displayName 自匹配 |
| equals [O] → "o" | normalize 后等价 displayName 自匹配 |
| MgO | Materials/MgO + equals "MGO" |
| b → "b" | Treatments/b + equals "b"（独立保留，不合并进 baked） |
