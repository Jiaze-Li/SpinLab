# 统一全局 Sample 新建规范（手写 / HTML / XLSX 收口到唯一入口）

> **Document:** `Plan.md` · v1.0 · 2026-11-18  
> **Phase:** Plan（需求已收敛；尚未进入 Design，待用户确认后进入设计审查）  
> **Repository:** `Jiaze-Li/SpinLab`  
> **Task branch:** `fix/unify-sample-creation`（Draft PR；不以 PR 状态代表任何审查通过）  
> **Read-only repository baseline:** `origin/main@3ae29312`  
> **policy_sha:** `7f01e5a3ff53ed13ba763d684a098c0989425ec4`（已读取 `engineering-workflow/README.md` 与 `engineering-lead/skill.md`）  
> **授权档位：** `只出方案`（已授权将 Plan 落盘并开草稿 PR；Design、Code 与合并尚未授权）  
> **Authority:** 本 `Plan.md` 全文为本任务冻结需求依据；PR 描述中的 Brief 仅为摘要。

---

## 1. 要解决的真实问题与目标

目前 SpinLab 存在多套并行的 Sample 创建与编号路径：

1. **桌面手写新建与 HTML/手机端新建**已按新规范生成 `smp_` 开头的永久随机编号；
2. **XLSX 导入**（Registry 同步与相关生长记录导入）仍绕开统一新建规范，直接用“批次 + 衬底语义”拼接出旧格式 `Sample Key` 作为主 `id` 与目录名，且没有生成 `smp_` 编号；
3. Library 界面直接把 `sample.id` 展示为 `Sample Key`，导致旧格式 key 在 UI 中暴露。

**目标：** 全局只保留**唯一一个**标准的 Sample 创建规范与入口，手写、HTML、XLSX 及未来新增的所有创建渠道都只负责把输入整理好并交给该唯一入口，由它统一按新规范生成 `smp_` 编号并完成创建；XLSX 来源样品通过独立映射字段保留与 Excel 行的对应关系；已有老样品原地兼容、不迁移，并在 Library 界面隐藏旧格式 key。

---

## 2. 用户、场景与失败代价

- **主要用户：** SpinLab 单人科研工作流（macOS 桌面端 + 手机网页端 + XLSX 实验表格）。
- **场景：** 从桌面手写新建、手机 HTML 表单新建、或导入/同步 XLSX 表格新建样品；重复同步同一份 XLSX；在 Library 中浏览、搜索并打开新老样品的测量与出图。
- **失败代价：**
  - 重复同步同一份 XLSX 时重复建出多个相同样品；
  - XLSX 同步误覆盖或删除手写 / HTML 新建的样品；
  - 既有老样品及其历史测量结果、出图记录无法读取或丢失。

---

## 3. 已核实的当前基线（静态事实，非运行 PASS）

- 桌面手写新建（`CreateNativeSampleSheetView`）与 HTML/手机新建（`PhoneSamplePickup`）均已调用 `NativeSampleCreationService.createSample(...)`，生成 `smp_` + UUID 作为 `id` 与 `sampleUID`，`origin = "native"`。
- XLSX Registry 解析（`LibraryRegistryParser`）直接构造 `LibrarySample`，使用 `LibrarySubstrateParser.sampleKey(batchId:substrate:)` 生成旧格式 `batchId|treatments|material|orientation` 作为 `id`，`sampleUID` 为 `nil`。
- `LibraryDiffEngine` 当前仅按 `sample.id` 匹配已有样品。
- `LibraryDetailView`、`LibrarySearchViews`、`LibraryViewComputationService` 当前无条件将 `sample.id` 显示为 `Sample Key` 行。

---

## 4. 硬性边界约束

1. **唯一创建权威（Single Creation Gateway）：**
   - 禁止任何上游入口（手写表单、HTML/手机、XLSX 解析器或未来新渠道）自行 `new` 出 `LibrarySample`、自行生成主键或自行落盘。
   - 全仓只保留**唯一一个**标准新建样品规范/入口，所有渠道只做输入适配并委托该入口创建。
2. **遵守《数据骨架》（`docs/architecture/spinlab/execution/SKELETON.md`）：**
   - 遵循 K1–K4、K13：新样品编号 `smp_` 在创建时生成、不含业务含义、永不改变；同批次同衬底可并存；损坏/读不到索引时 fail-closed。
3. **老样品原地兼容：**
   - 遵守 `SKELETON.md`“现有旧库不搬家、不批量改写”——不改写既有老样品的文件夹名、`sample.json` 或历史测量/图索引。
4. **互不干扰 & 不改原 Excel：**
   - 手写与 HTML 新建样品绝不被 XLSX 同步覆盖或删除；
   - 不修改用户的原始 `.xlsx` 文件（不写回 `SampleUID` 列）。

---

## 5. 明确不做什么

- 不给已有老样品批量补发 `smp_` 或迁移旧目录、旧索引、旧 sidecar。
- 不在 `.xlsx` 文件中新增或写回 `SampleUID` 列。
- 不修改测量数据处理、拟合分析或出图渲染算法。
- 不引入多用户并发锁（遵守 `AGENTS.md` 单用户假设）。

---

## 6. 可观察的验收条件

- **AC-1（统一创建入口）：** 从 XLSX 首次导入的新样品不再绕开统一新建规范，统一生成 `smp_` 作为永久 `id` 与目录名，并在内部字段保留旧式“批次 + 衬底”来源映射。
- **AC-2（XLSX 重复同步不重样）：** 再次同步同一份 XLSX 时，通过内部来源映射找回对应的 `smp_` 样品并更新其属性，不重复创建第二个样品。
- **AC-3（手写 / HTML 与 XLSX 互不干扰）：** 手写或 HTML 新建的同批次同衬底样品，可与 XLSX 导入样品共存；再次同步 XLSX 不会覆盖或删除手写 / HTML 样品。
- **AC-4（Library UI 展示规则）：**
  - 有 `smp_` 编号的样品，Library 详情与搜索界面仅展示 `smp_...`，不暴露内部 XLSX 映射 key；
  - 没有 `smp_` 的老样品，Library 界面隐藏 `Sample Key` 一行。
- **AC-5（老样品兼容）：** 已有无 `smp_` 的老样品在界面中照常打开，原有测量、出图及既有 XLSX 同步照常工作；本地相关测试通过。

---

## 7. 已确认决定与待核实前提

- **已确认决定：**
  1. 全局新建样品收口到唯一创建规范/入口，统一生成纯随机 `smp_`；
  2. XLSX 来源新样品在库内保留旧式 key 作为内部映射（不修改原 XLSX 文件）；
  3. 老样品原地兼容、不批量迁移；
  4. Library UI 对无 `smp_` 的老样品直接隐藏 `Sample Key` 行。
- **待核实前提（Design 阶段核查）：**
  - `RegistryGrowthImportPlanner` / `RegistryGrowthMutationService` 等生长记录导入链路中，哪些地方依赖或构造旧式 `sampleKey`，如何统一接入或与新 `smp_` 映射兼容；
  - 现有测试中直接断言 `Sample Key` 展示或旧 key 构造的用例范围。

---

## 8. 授权范围

- **已授权：** 编写本 `Plan.md`、提交至任务分支并创建 Draft PR。
- **未授权（需用户明确回复后才可执行）：** 进入 **Design**（含 ReviewLoop `design` 审查）、**Code**（代码修改、本地测试、后续 commit/push）及 PR 合并。
