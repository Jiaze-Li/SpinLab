# Handoff: 规则管理架构清理

> 产出方：Claude（2026-04-25 19:xx，2026-04-25 21:xx 续会决策）
> 消费方：另一个 terminal 里的 agent / 后续会话
> 工作目录：`/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab`
> 当前分支：main（已干净，仅 3 个 bundle 配置文件被本次会话改动尚未提交，详见"接手前必读 §C"）
> **版本归属：5.1.5 — 规则管理统一 + 自动同步基础设施**（Jack 已确认）

---

## 0. 决策更新（2026-04-25 续会话，最高优先级）

> 本节是 Jack 在续讨论中拍板的最终方案，**和下方原文有冲突时以本节为准**。下方 §1–§7 保留作为背景与实现参考，不再代表完整方案。

### 0.1 顶层原则（已上升为 App 顶层规则）

> **"你看见的，就是 App 设置的。"**
> 所有规则——包括平时几乎不改的——都必须在 UI 里看得见、改得动。

要写进 `docs/philosophy.md` 顶层原则区。

### 0.2 后台架构（最终形态）

- 一类规则一个文件，**没有"主文件 + 分文件"叠加**。
- 当前 6 类规则 → 改完后 6 个文件，每份在 `Sources/SpinLabApp/config/`（仓库）和 `~/Library/Application Support/SpinLab/config/`（runtime）各放一份，**两边字节级一样**。
- 所有规则用同一套保存路径、同一套自动同步机制、同一种格式约定、同一种备份/回滚策略 → 后台逻辑上是"一处管理"。
- 6 类清单（最终命名以实现时为准，但语义对照如下）：
    1. 文件名解析规则（含 conditions / 单位 / token map）
    2. 样品 ID 识别规则
    3. 工作流匹配规则
    4. 衬底名归一化规则
    5. 测量标签规则（识别 AMR/PHE/Rxx/Rxy 等测量种类）
    6. 工作流 ID 生成策略（preferredAlphabet / fallbackPrefix，目前只 2 个参数）

### 0.3 UI 架构（最终形态）

- **单一统一入口**：一个"规则管理"面板，内含 6 个分区/Tab，对应上述 6 类规则。
- **入口位置**：Inbox 中间列、"Inbox Operations" 标题旁边的**文字按钮**（不是图标）。
- **不做全局菜单入口**。
- 现有 3 处分散入口 **全部拆掉**，不保留快捷跳转：
    - Workbench 顶部的独立 "Rules Handbook" 窗口 → 删
    - WorkflowRegistryView 里的 "Match Rules" 区段 → 删
    - InboxExplicitRulesSheet 弹窗 → 删
- 全部 6 类规则的编辑能力在新统一面板里**重新实现**，不要在烂地基上改良。其中：
    - 4 类已有 UI 实现可作功能参考（不是代码移植）
    - 2 类（测量标签、工作流 ID 策略）需要从零设计 UI

### 0.4 自动同步机制（最终形态）

- UI 一按保存 → 写本地 → 自动写仓库镜像，全程 App 自完成，**用户不点任何"同步"按钮**。
- 反向同步（仓库版本新于本地，例如另一台电脑 pull 回来后）：用**内容指纹（哈希）**判断，**不用文件 mtime**（git 不保留 mtime，会误判）。
- 所有写入路径 atomic，写入前自动备份带时间戳的副本。
- 仓库目录指针机制：runtime 侧一个指针文件（一行 UTF-8 写仓库 config 目录绝对路径），找不到/为空就跳过镜像写入，不报错。

### 0.5 迁移策略（最终形态）

- 一次性迁完，**不留中间状态**：
    - 把现有"主文件 + 分文件"叠加合并为"一类一份"
    - 同时把 runtime 主文件从 v0 扁平 schema 升级到与 bundle 一致的 v1 嵌套 schema
    - 上述两步**合并为一次启动迁移**，不分两阶段（避免半成品中间态）
- 迁移代码看到任何旧形态都直接重写成最终形态。
- 迁移前自动创建 `.backup-<ts>` 副本，迁移成功才删原文件。
- 旧 schema 的 decoder **保留为只读路径**用于迁移；写入路径只走新 schema。

### 0.6 拆分顺序（最终 4 次会话）

1. **会话 1**：先落地 §C 的 3 个待提交 bundle 改动 → 然后拆掉所有现有规则 UI（3 处）+ 删除后台冗余分文件、半成品代码、`scripts/sync_runtime_rules_to_bundle.sh` → 文件合并迁移到新结构。**此次结束后规则 UI 暂时不可用，是预期的**（下一次会话补上）。
2. **会话 2**：新统一面板骨架（Inbox 入口 + 6 分区路由）+ 接 4 类已有规则的编辑能力。
3. **会话 3**：从零建"测量标签" + "工作流 ID 策略"两个分区的 UI。
4. **会话 4**：自动同步引擎（双写 + 内容指纹反向同步）+ 完整测试 + 实机走一遍（启动 / 保存 / pull 后覆盖 / 回滚 / 指针文件缺失等场景）。

### 0.7 工作量与版本

- 总工作量：**16–20 小时**。
- 版本归属：**5.1.5**（跨区域技术债 + 基础设施）。需在 `docs/V5_ROADMAP.md` 5.1.x 段下新增 5.1.5 条目。
- 不要尝试在一次会话里全做完。

### 0.8 设计决策的来源（避免后续 agent 推翻）

这些决策都是 Jack 与 Claude 在续讨论中明确拍板的，包含他给出的理由：

- **"自动同步而非手动按钮"** —— Jack 原话："我不想我按一下同步，我要自动同步。" 不要再提"加一个手动按钮"作为替代方案。
- **"全部规则都要在 UI 里看得见"** —— Jack 原话："这个 app 的最高规则就是我看见的就是 app 设置的。" 即便像工作流 ID 策略只有 2 个参数、几年改一次，也必须在 UI 里。
- **"统一入口而不是分散"** —— Jack 原则："如果规则在后台是一处管理，那 UI 也做一个入口。" 后台改完后逻辑上是一处管理 → UI 也只做一处。
- **"删现有重建，不在烂地里改良"** —— Jack 原话："现在有的清理掉，全部重新做，不要在烂地里改良，好好做一个清楚结构的。" 不要尝试把新机制叠在现有 UI 上。
- **"入口放 Inbox，不做全局"** —— Jack 明确选择，不要改成 SpinLab 顶部菜单。

---

## 1. 背景（必读）

Jack 是 SpinLab 唯一使用者。当前规则管理架构散落在多个文件、多目录、两套不同 schema 上，今天 4·25 因此踩了一个坑（用户配置被静默丢弃 + 规则文件被 sibling agent 整份覆盖丢了 shift 等条目）。

Jack 拍板的目标哲学：

> **"UI 是真相的唯一来源，bundle 和 runtime 永远是这份真相的两个镜像，没有第二种状态。"**

具体诉求：UI 按一下保存 → runtime 立刻更新 → bundle 也立刻跟着更新，全部由 App 自己完成，Jack 不用记得跑任何脚本。

---

## 2. 现状（架构 audit 结论）

### 2.1 文件分布

`Sources/SpinLabApp/config/`（bundle，仓库内，跟 git）：
- `filename_rules.json` ← v1 嵌套 schema（`{ version, shared, library, inbox }`）
- `sample_id_rules.json`
- `workflow_match_rules.json`
- `substrate_rules.json`
- `measurement_tag_rules.json`
- `workflow_id_policy.json` ← bundle-only，runtime 没有

`~/Library/Application Support/SpinLab/config/`（runtime，本地）：
- `filename_rules.json` ← v0 扁平 schema（顶层 12 个键）
- `sample_id_rules.json`
- `workflow_match_rules.json`
- `substrate_rules.json`
- `measurement_tag_rules.json`
- ❌ `conditions_rules.json` ← 代码读它/能写它，但**两个目录都从未真出现过**（半成品迁移残留）
- ❌ `workflow_id_policy.json` ← runtime 没有

### 2.2 核心问题

1. **同一份概念多处存放**：例如 sampleId 同时在主文件和分文件里，靠"分文件赢"的隐式约定生效，长期漂移。
2. **bundle 和 runtime 主文件 schema 不一致**：项目 sync 脚本（`scripts/sync_runtime_rules_to_bundle.sh`）显式跳过主文件，原因就是 schema 不同。
3. **存在半成品迁移路径**：`conditions_rules.json` 这个分文件代码层面齐全（`RulesConfigPaths` / `SeparatedOverrideReader.readConditions` / `ConditionRulesHandbookStore.saveConditions`），但 UI 永远不会写它。
4. **bundle 和 runtime 没有自动同步**：UI 改的只到 runtime，bundle 是死的。
5. **4·25 的根因**：`9bf58f2` 清理提交把 `ConditionRules.init(from:)` 删了，让 displayLabels 等键变必需，导致 runtime 解码失败 → 静默跌回 bundle。已被 `b52906d` 修复，但暴露了"叠加层架构"难以排错的本质问题。

### 2.3 今天会话已经发生的运维动作

- runtime/`filename_rules.json` 已从 `legacy-backup-20260425-170331` 完整恢复（shift / Oe / 单位组等都回来了）
- 已将 runtime 解析规则**手工**合并到 bundle/`filename_rules.json` 的 inbox/shared 区（保留 bundle 独有的 library/shared.substrate/version）
- 已运行 `scripts/sync_runtime_rules_to_bundle.sh`，分文件 sample_id_rules / substrate_rules 也已同步进 bundle
- 桌面 .app 已重编译（debug，v5.5.0 (202604251941)）
- bundle 那 3 个改动尚未 commit（见 §C）

---

## 3. 任务清单（按建议执行顺序）

### Step 1：先把待提交的 bundle 改动落地

**目标**：把今天会话已经做的那 3 个 bundle 改动提交，让仓库回到干净状态、再开始重构。

**改动文件**：
- `Sources/SpinLabApp/config/filename_rules.json`
- `Sources/SpinLabApp/config/sample_id_rules.json`
- `Sources/SpinLabApp/config/substrate_rules.json`

**做法**：
1. `cd /Users/jack/Downloads/scripts/Codex SpinLab/SpinLab`
2. `git status --short` 确认范围（应只有上面 3 个文件 + 未跟踪的 `.claude/`）
3. `git diff` 浏览改动（shift 条件定义 + Oe 单位 + sampleId 收窄 + substrate "BAKE/BAKED" → "baked" 等）
4. 提交，commit message 建议：
   - 标题：`chore(rules): align bundle with runtime — restore shift, Oe, substrate normalizations`
   - 正文要点：runtime 自 4·25 恢复后的真相镜像；列出主要差异（shift 条件定义新增 / field 加 Oe / sample_id 收窄到 PN|PT|SL / substrate "BAKE/BAKED" 值从 b 改 baked / "O/ORIGIN/ORIGINAL" 三条合一）
5. **不要 push**，让 Jack 自己 push

**验收**：`git status` 干净。

---

### Step 2：删掉"分文件"机制

**目标**：每类规则只存一处，消除"主文件 vs 分文件"叠加。

**核心改动**：
1. 把 `sample_id_rules.json` / `workflow_match_rules.json` / `substrate_rules.json` / `measurement_tag_rules.json` 的内容并回主文件 `filename_rules.json` 对应区段
2. 删除 `RuleLoader.swift` 里 5 个 `resolveOverrideURL(filename: "*_rules.json")` 分支
3. 删除 `SeparatedOverrideReader.swift` 整个文件（或只保留 schema 定义，移除 read 方法）
4. 删除 `RulesConfigPaths.swift` 里那 5 个分文件路径属性（保留 `ruleURL` 主文件）
5. 删除 `ConditionRulesHandbookStore.swift` 里：
   - `saveConditions(_:approvalToken:)` 整个方法（半成品分文件路径）
   - `loadSeparatedWorkflowMatchRules` / `loadSeparatedSubstrateRules` / `loadSeparatedMeasurementTagRules` 等
   - 所有指向 4 个分文件 URL 的属性
6. 删除 `scripts/sync_runtime_rules_to_bundle.sh`（不再需要）
7. 文件系统层：把现存的 runtime 4 个分文件**合并回 runtime 主文件**，然后删掉它们（提供一次性迁移逻辑：App 启动检测到分文件存在 → 合并到主文件 → 删除）
8. 同步把 bundle 4 个分文件删掉

**验收**：
- 仓库里只剩一个 `filename_rules.json`（外加 `workflow_id_policy.json`，那个是另一回事，§Step 4 处理）
- 跑全套 tests，特别注意 `V225RulesConfigContractTests` / `V534*` / 任何 RuleLoader 相关
- 桌面构建跑一遍：`bash scripts/build_desktop_app.sh`
- 启动 App、打开规则手册、编辑 + 保存一条规则、确认 runtime 主文件正确写入、UI 立即生效

**风险**：现存 runtime 分文件迁移过程出错。建议迁移前自动做一份带时间戳的备份（在原目录里 `.backup-<ts>` 文件），不动后才删原文件。

---

### Step 3：runtime 改用嵌套 schema（与 bundle 一致）

**目标**：让 runtime/`filename_rules.json` 跟 bundle 长得字节级一样，可以直接 `cp` 同步。

**核心改动**：
1. 当前 bundle 用 `{ version, shared, library, inbox }`；让 runtime 写入也走同一格式
2. `FilenameRuleSet` 的 `init(from decoder:)` 已经能 decode 两种 schema（v0 扁平 / v1 嵌套），保留 v0 解码作为**只读迁移路径**
3. App 启动时检测 runtime 主文件 schema：如果是 v0，自动迁移成 v1（写回原路径）。迁移前同样自动备份
4. 所有写入路径（`save(_:approvalToken:)` 之类）一律按 v1 嵌套写
5. `RuleCanonicalizer.migrateUserRuleJSONToCanonical` 扩展或替换，覆盖 v0→v1 的整体迁移
6. **删掉已经没人写 v0 的代码路径**（保留 decode 兼容只读，写入路径一律 v1）

**验收**：
- 一次性自动迁移生效后，`diff <(cat runtime/filename_rules.json) <(cat bundle/filename_rules.json)` 应只剩**实际内容差异**，没有结构差异
- UI 保存若干条规则后 runtime 仍是合法 v1 嵌套
- 老 v0 文件载入仍能解码（兼容性测试用 fixture）

---

### Step 4：UI 保存自动镜像到 bundle + 指针文件

**目标**：UI 按一下保存 → runtime 立刻更新 → bundle 也立刻跟着更新。

**核心改动**：

#### 4.1 指针文件机制
- 约定一个指针文件路径：`~/Library/Application Support/SpinLab/config/.bundle_mirror_target`
- 内容：一行 UTF-8 文本，写仓库内 `Sources/SpinLabApp/config/` 的绝对路径
- App 启动时读取这个指针文件；不存在或文件为空就认为"无镜像目标"，跳过同步（不报错）
- 文档里告诉 Jack 怎么手动一次性配置（一次写好，重装电脑前都不用动）

#### 4.2 双写逻辑
在所有规则保存的代码出口（`ConditionRulesHandbookStore.save`，以及 §Step 2 合并后的所有"曾经写到 runtime"的入口）插入：
```
1. 写 runtime（原行为，保持 atomic）
2. 读取指针文件 → 得到 bundle 目录绝对路径
3. 检查目录可写
4. 把刚写的 runtime 文件原样拷到 bundle 目录（保持 atomic：写到 .tmp 再 rename）
5. 拷贝失败不阻塞 UI 流程，只 log warning
```

#### 4.3 启动时反向同步（bundle 更新后自动接受）
- App 启动加载规则时，比较 bundle/`filename_rules.json` 和 runtime/`filename_rules.json` 的 mtime
- 若 bundle 严格更新（你 git pull 拉到了新版），用 bundle 整份覆盖 runtime
- 这步要谨慎：必须确保已经做完 §Step 3（schema 一致）才能直接覆盖
- 备份原 runtime 到 `.replaced-by-bundle-<ts>`，万一你不想接受这次 pull 还能回滚

**验收**：
- 在 UI 改一条规则，立刻 `git diff` 仓库 bundle 文件，看到对应改动
- 删掉指针文件，UI 仍能正常保存（只 log），不报错
- 模拟"上游 pull 进新规则"：人工修改 bundle 文件 + 推后 mtime → 重启 App → runtime 应被覆盖、UI 显示新规则

---

### Step 5：处理 `workflow_id_policy.json`

**目标**：要么让它也走"runtime + bundle 双写"，要么明确它是"开发者维护、不归用户改"。

**做法**：
1. 先看代码里这文件被读到哪些路径、是否有 UI 暴露给用户编辑
2. 如果**没有 UI 编辑入口** → 就保持 bundle-only，加注释说明，这事就完了
3. 如果**有 UI 编辑入口** → 给它在 runtime 也开一份，纳入 §Step 4 的双写体系

---

### Step 6：清理 4·25 的临时备份

工作完成后清理：
- `~/Library/Application Support/SpinLab/config/filename_rules.json.legacy-backup-20260425-170331`
- `~/Library/Application Support/SpinLab/config/filename_rules.json.pre-restore-20260425-194047`

确认 `git log` 里能追溯到当时恢复的内容（Step 1 的 commit 应该已经把 shift 等内容固化进仓库）后再删。

---

## 4. 接手前必读

### A. 文档要更新
- `docs/philosophy.md` —— 加入"UI 是规则真相的唯一来源 + bundle 和 runtime 永远镜像"这条原则
- `docs/features.md` —— 用户可见行为变化（"保存即同步到仓库"是新功能）
- `docs/history/v5xx_rules_consolidation.md` —— 新增一篇，记录这次重构的动机（含 4·25 事件回顾）和决策
- `docs/known_issues.md` —— 把"半成品 conditions_rules.json"这条已知问题标记为已解决

### B. 测试要扩展
- 已有 `V225RulesConfigContractTests` 覆盖了 `displayLabels` 缺失的 decode 场景，要扩展：
  - v0 → v1 schema 一次性迁移正确性
  - UI 保存后 runtime 和 bundle 字节级相等
  - 指针文件不存在时保存仍成功
  - bundle mtime 新于 runtime 时启动后正确反向同步
  - 启动时"分文件→主文件"一次性合并（§Step 2 迁移路径）

### C. 当前未提交的 bundle 改动
本次会话改了但没 commit 的 3 个文件：
- `Sources/SpinLabApp/config/filename_rules.json`（合并 runtime 主文件解析规则）
- `Sources/SpinLabApp/config/sample_id_rules.json`（sync 脚本同步）
- `Sources/SpinLabApp/config/substrate_rules.json`（sync 脚本同步）

执行 §Step 1 之前不要再动 bundle 文件。

### D. 不要做的事
- 不要在 §Step 3 完成前真的让 runtime 写 v1 嵌套（§Step 2 完成后 decoder 已经简化，但 v0 写入路径**保留**直到 §Step 3 测试覆盖到位）
- 不要 push 任何 commit；所有 commit 留给 Jack 本地审一遍再 push
- 不要直接覆盖 runtime/`filename_rules.json`：每次写都要 atomic + 自动备份
- 不要删除 `~/Library/Application Support/SpinLab/config/` 下任何 `.legacy-backup-*` / `.pre-restore-*` 文件，直到 §Step 6 明确清理时机

---

## 5. 完成的判定

全部完成后这些都成立：
1. 仓库内 `Sources/SpinLabApp/config/` 只有一个 `filename_rules.json`（+ 可能保留的 `workflow_id_policy.json`）
2. `~/Library/Application Support/SpinLab/config/` 也只有一个 `filename_rules.json`
3. 两份文件 schema 完全一样，可以 `diff` 出零差异（如果 Jack 没在 UI 改任何规则的话）
4. Jack 在 UI 里改一条规则点保存 → `git diff` 立刻能看到 bundle 改动
5. 现有所有 tests 通过，新增的覆盖项也通过
6. 桌面 build 通过、启动 OK、规则手册功能正常

---

## 6. 工作量估计

- §Step 1（commit 待提交内容）：< 10 分钟
- §Step 2（删分文件）：约 1–2 小时（代码删除多、测试要全跑）
- §Step 3（schema 统一 + 迁移）：约 1–2 小时（最需要小心，要测）
- §Step 4（双写 + 指针 + 反向同步）：约 1–2 小时
- §Step 5（policy 文件评估）：约 30 分钟
- §Step 6（清理备份）：< 10 分钟

总计约 4–7 小时，最好分两次会话做：第一次 Step 1+2，第二次 Step 3+4+5+6。

---

## 7. 工作完成后

- 删掉本 handoff 文件 `tmp/handoff-rules-architecture-cleanup.md`
- 在 `docs/history/` 新增对应的 history entry（已在 §A 提及）
- Push 由 Jack 本人执行
