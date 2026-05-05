# Handoff: 5.1.16 B 包 — Library Recompute Banner 假阳性修复

**版本**：5.1.16 | **范围**：B 包（Library 蓝色横幅假阳性，与 A 包独立 handoff/独立 PR）
**主笔**：Codex（诊断 + 修复 + 回归测试同一作者）| **Acceptance review**：Claude
**前置文档**：`docs/V5_ROADMAP.md` 5.1.16 段；`tmp/2026-05-05-5116-baseline.md` H 段（事实层现象 + 入口路径）；`tmp/2026-05-05-5116-rhythm-codex-review.md`（节奏对抗结论）
**节奏铁律（来自 Codex 节奏评审）**：先固定一个能失败的回归入口，再实施修复

---

## §1 现象（不展开 root cause 假说）

Library 蓝色横幅 "X 个测量基于旧规则可重算"：

- 横幅显示有旧规则可重算的测量（`recomputeStaleCount > 0`）
- 用户点开 recompute 预览面板后，所有测量已是最新规则、无需重算（diff 列表为空 或 全等价）
- 判定与真实数据状态对不上 — 假阳性
- 数据无损害；用户体验是"每次出现都白干扰"

实证现象由 Jack 在生产观察（TASK_BOARD 5.1.15h 验收观察行登记）；Stage 1 baseline 仅记入口路径，未做 root cause 推断。

---

## §2 范围

### Scope Allowed（根因导向最小闭包）

**默认范围（优先限于以下文件）**：
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Recompute.swift`（77 行）
- `Sources/SpinLabApp/Library/Services/LibrarySidecarService*.swift`（含 `computeStaleCount` / `computeRecomputeDiff` 真正判定逻辑；具体文件由 Codex grep 定位）
- `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift`（含 `recomputeStaleCount` / `recomputeDismissedFingerprintByRoot` / `recomputeDiffItems` 等字段）
- `Tests/SpinLabAppTests/`（新增 V5116 回归测试 + 修改既有相关 case 仅在必要时）

**条件扩展（只有在 Step 2 诊断证据指向时才允许，且 commit / acceptance brief 必须记录证据）**：
- 若 root cause 在 sidecar 解析路径 → 可扩入 `Sources/SpinLabApp/Library/Services/LibrarySidecarParser*.swift` / sidecar fixture 写入器
- 若 root cause 在 fingerprint contract / provider → 可扩入 `Sources/SpinLabApp/Domain/Rules/RuleSetFingerprint*.swift` 或 `SpinLabRuleProvider*.swift`（按 Domain 三 Tier 规则就地）
- 若 root cause 在 sidecar 写入路径（backfill/save） → 可扩入对应 service

**未列出文件需扩入** → halt，向 Jack 申报证据 + 申请 Scope 扩展，不自行越界。

### Scope Denied
- 禁止动 A 包 §1 列的 5 个测试文件（A/B 包独立）
- 禁止改章程类（`workflow.md` / `dispatch.md` / 项目根 `CLAUDE.md` / `specs/**`）
- 禁止改 ROADMAP / TASK_BOARD 之外的 docs（除本 handoff 归档时由归档者搬迁）
- 禁止把诊断 / 修复 / 回归测试拆给不同作者（Codex 主笔同一作者完成三件事；可拆派发但不可换作者）
- 禁止跳过 §3 的"先复现失败再修"步骤
- **禁止无证据重写 `computeStaleCount`** — 必须先有 Step 1 失败回归 + Step 2 诊断指向具体脱节点再修；不做无证据的算法重构
- 每个 Step 开始前必跑 `git status --short`；如出现非 Scope Allowed（含已批准的条件扩展）文件 halt 报告

---

## §3 执行步骤（Codex 主笔）

### Step 1 — 失败回归测试先行（[HARD]，独立派发完成）

在 `Tests/SpinLabAppTests/V5116RecomputeBannerFalsePositiveTests.swift` 新建一个测试 case，构造一个能稳定**复现假阳性**的场景。

**前置状态构造（[HARD]，避免自相矛盾断言）**：测试在断言前必须先观测到 `staleCount > 0` 且 `computeRecomputeDiff(rootURL:)` 返回空或全等价 — 这两个事实共存才是 Jack 报告的假阳性入口。如果只断言"diff 非空"而没有先证明 `staleCount > 0`，测试只是在测算法不变式，不是复现 bug。

**测试结构骨架**：

```
1. 起 fixture library 根目录（temp dir，按 5.1.15h 测试隔离用 LibrarySettingsStore(settingsURL:) 注入）
2. 准备 N 个 sidecar 文件 + 一个 ruleSetFingerprint 状态
3. 调 refreshRecomputeStaleCount() → 观察 staleCount，断言 > 0（复现"横幅显示有旧规则测量"）
4. 调 openRecomputePreview() → computeRecomputeDiff(rootURL:) → 观察 diff
5. 断言：staleCount > 0 时 diff 应非空（修前必 fail，证明假阳性入口）
```

**复现场景候选**（Codex 自行诊断选最贴近生产的一种或多种）：
- A. sidecar 文件 fingerprint 等于当前 ruleSet fingerprint，但某个间接判据让 `computeStaleCount` 错误返回正数
- B. dismiss fingerprint 持久化与 stale 判定使用的 fingerprint 不一致
- C. staleCount 计算包含已被规则升级前 dismiss 的记录
- D. 其他 — Codex 诊断决定

**红灯 commit 协议（[HARD]）**：

1. 红灯 commit **只允许**新增/修改回归测试，**不允许**含修复代码（任何 Sources 改动）
2. commit 前跑目标 filter，把失败输出**完整**保存到 `tmp/2026-05-05-5116-H-red-test.log`（供 Claude acceptance review checkout 复验）
3. 失败范围**必须是目标 case**；如出现无关失败 → halt（说明环境或测试构造有问题）
4. commit message: `test(5.1.16-H): regression — recompute banner false positive reproduces`
5. 此 commit push 后**派发结束**（拆派发协议 §3.5）

### Step 1.5 — 派发拆分协议（[HARD]）

Codex 主笔三件事仍由**同一作者**完成（不换人）；但**允许且推荐拆成两次派发**避免 30-turn 死线：

- **派发 1**：仅 Step 1 — 完成红灯回归 commit 后退出
- **派发 2**：Step 2-4 — 在同一作者上下文继续诊断 + 修复 + 回归转绿 + suite + desktop build

两次派发之间不更换作者、不转交诊断结论；派发 1 退出前 commit 已 push、log 已保存到 tmp，派发 2 启动时把这两件事作为前置事实读入。

### Step 2 — 诊断 + 最小修复

1. 读 `LibrarySidecarService.computeStaleCount(rootURL:currentFingerprint:)` 实际算法
2. 对比 `computeRecomputeDiff(rootURL:)` 的判定逻辑
3. 定位两者判据脱节的具体点（fingerprint 比对 / sidecar 状态读取 / 缓存失效时机 等之一）
4. **最小针对性修复** — 优先让两个判据使用同一事实源；不做大重构
5. 修复 commit message: `fix(5.1.16-H): <root-cause-summary> — banner now consistent with recompute diff`

### Step 3 — 回归测试转绿 + 跑相关 suite

- 修复后回归测试转绿
- 跑 `swift test --filter V5116RecomputeBannerFalsePositive` 通过，stdout 保存到 `tmp/2026-05-05-5116-H-green-test.log`
- 跑相关上下文 suite 不回归（**存在则跑、无匹配 ≠ 失败**）：
  - `swift test --filter LibraryFeatureStore`（5.1.13/15 的 facade tests）— stdout 保存 `tmp/2026-05-05-5116-H-libraryfeaturestore.log`
  - `swift test --filter LibrarySidecar` — stdout 保存 `tmp/2026-05-05-5116-H-librarysidecar.log`
  - `swift test --filter Recompute` —— 如返回 "0 tests" 视为无匹配（不当失败处理），保存 stdout 即可
- 实际 fail（非"无匹配"）→ halt 并附 log 证据

### Step 3.5 — Code Map 登记（[HARD]，仅当新增 Sources/**/*.swift 时）

如 Step 2 修复涉及新增 swift 文件（含 Domain Tier 1/2 物理迁移产生的新文件），按项目根 `CLAUDE.md` "Adding New Swift Code" 4 步 SOP 登记到对应 `docs/architecture/<region>/<layer>.md` 的 `## Code Map` 段。pre-commit hook 会校验，未登记 commit 失败。修改既有文件核心职责时按 Session Closeout 第 6 条反查 Code Map 注释是否仍准确。

### Step 4 — UI 路径生产验证

修复涉及 UI 行为变更（横幅显示）→ 必须 desktop 重 build 验证：

```bash
./scripts/build_desktop_app.sh debug
```

构建产物到 `~/Desktop/SpinLab.app` 后，由 Jack 在生产 Library 上手动验证横幅显示与 recompute diff 一致（B 包验收时 Jack 走一次）。

---

## §4 Acceptance Review（Claude 责任）

Codex 完成 Step 1-4 后，Claude 独立做：

1. **Diff 评审**：所有 commit 是否 §2 Scope Allowed（含已批准条件扩展） / commit message 是否反映 H 编号 / 是否拆 squash
2. **失败先行验证**：用临时 worktree（`git worktree add ../SpinLab-5.1.16-h-verify <commit>`）checkout Step 1 commit，跑回归测试，确认 fail；checkout Step 2 commit，确认 pass — 复现 → 修复链条完整。**禁止在主工作树 `git checkout <commit>` 污染当前状态**；验证完毕 `git worktree remove` 清理
3. **回归测试质量**：是否真复现 Jack 报告的现象（staleCount > 0 + diff 空 共存），还是只测了某个内部不变式
4. **修复最小性**：fix 是否就 root cause / 还是搂草打兔子做了无关重构 / Scope 条件扩展是否有 commit 证据
5. **build 验证**：`./scripts/build_desktop_app.sh debug` 通过
6. **log sanity**：`tmp/2026-05-05-5116-H-red-test.log` / `-green-test.log` / `-libraryfeaturestore.log` / `-librarysidecar.log` 存在且内容一致
7. **Code Map 登记**：如 Step 2 新增 `Sources/**/*.swift`，对应 `## Code Map` 是否登记
8. **可要求补测**：如发现回归测试覆盖不全（例如只测了 dismiss fingerprint 一种场景，其他场景未覆盖），可要求 Codex 补；但**不主写**回归测试

输出 `tmp/2026-05-05-5116-B-acceptance.md`：adopt / adopt-with-fixes / reject + must-fix（如有）。

---

## §5 失败 fallback

- Step 1 写不出能稳定复现的回归测试（30 turn 内未收敛） → halt，报 Jack，附诊断进度；不带着无回归保护的 fix 上线
- Step 2 找不到清晰 root cause（多场景叠加） → halt，给 Jack 三选项（修最常见场景 / 重写算法 / 推下版本），由 Jack 拍板
- desktop build 失败 → 按 fail 处理，不交付

---

## §6 完成定义

- [ ] V5116RecomputeBannerFalsePositiveTests 新建并能复现失败（红灯 commit，派发 1 产出）
- [ ] 红灯 stdout 落 `tmp/2026-05-05-5116-H-red-test.log`
- [ ] root cause 修复 commit 落地（绿灯 commit，派发 2 产出）
- [ ] 绿灯 stdout 落 `tmp/2026-05-05-5116-H-green-test.log`
- [ ] 相关 suite 不回归（log 全保存到 tmp/）
- [ ] 如新增 Sources swift 文件 → 对应 region/layer `## Code Map` 已登记，pre-commit hook 通过
- [ ] desktop app 重 build 通过
- [ ] Jack 生产验证横幅显示与 recompute diff 一致
- [ ] Claude acceptance review 产出（用临时 worktree 做 checkout 验证，验毕清理）
- [ ] Claude 裁决 adopt 或 adopt-with-fixes（fix 全并入）
- [ ] TASK_BOARD B 包行状态：s2 落盘后「方案完成 (s2)」→ 派发 1 commit 落地后「方案执行中 (s2)」→ B PR 合后「验收中」→ closeout 删
- [ ] PR 提交（B 包独立 PR）

**TASK_BOARD 同步状态（s1/s2 落盘时点）**：
- s1 落盘（2026-05-05）：B 包行已翻「方案完成 (s1)」+ 指针 → 本 handoff
- s2 落盘（adopt-with-fixes 修订并入）：状态升级为「方案完成 (s2)」

---

## §7 与 A 包关系

- **默认调度**：A 包完成且 PR 合并后再启动 B 包；Jack 显式改调度时才并行（避免双 PR 同期 review 心智负担）
- A 包是机械性测试更新、规模小；B 包含诊断、规模大且不可预测 — 串行让 A 快速清账面、B 拿完整诊断时间
- 5.1.16 closeout（ROADMAP `[x]` + TASK_BOARD A/B 两行整体清理 + history/INDEX 加一行）等 A、B 都合并后一次性做
