# 任务 9：废纸篓与分级删除（Zotero 软删除模式）

对应原 5.6.4 废纸篓与分级删除。前置：任务 2 已合并（PR #195）。
流程：**先设计**（涉及新增废纸篓状态、Registry 同步隔离与彻底删除边界，需先过一轮 design 审查再实现）。

## 目标

恢复可用的样品删除能力，采用“软删除进废纸篓、可一键恢复、永久保留不自动清空、手动彻底删除才删盘”的 Zotero 模式，并按样品是否有数据分级确认。

## 需求

1. **空样品直接进废纸篓**：没有任何测量数据、没有图、没有手填参数的样品，点击删除后直接移入废纸篓，不需要二次确认。
2. **有数据样品二次确认**：已有测量数据、图或手填参数的样品，点击删除时弹出二次确认提示；取消则不动，确认后移入废纸篓。
3. **软删除不动物理文件**：移入废纸篓只打状态标记，**原地保留样品物理文件夹不搬动**，不删除磁盘上的任何测量或图表文件（避免未建链接表前误伤共享图表）。
4. **视图与搜索隔离**：进入废纸篓的样品，从常规 Library 列表、普通搜索、Workbench 选样中全部隐藏；只在专门的“废纸篓”视图中可见。
5. **永久保留不自动清空**：废纸篓里的样品**永久保留**，不做超期自动清理。
6. **一键还原**：在废纸篓中点击“还原”，撤销废纸篓标记，样品直接回到原批次与常规视图中；因物理目录未移动，不存在“原位置被占用”的冲突。
7. **手动彻底删除 / 清空废纸篓**：在废纸篓中对单个样品点“彻底删除”或点“清空废纸篓”，必须弹出不可逆二次确认；确认后才物理删除样品自身目录（若存在被其他正常样品引用的共享文件，不得误删）。
8. **Registry 同步隔离**：废纸篓中的样品在 Registry 同步时既不重新复活为正常样品，也不被物理删除；表格缺行仍受任务 2 的安全护栏保护。

## 不做

- 自动定时清空废纸篓（如 30 天自动删除）。
- 批次（Batch）级一键物理清空。
- 还原时重定位到“另一个新批次”。
- 引入链接表或 SQLite（留给任务 5）。

## 代码现状（`main`，Agent 开工前须自行复核）

- `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift`：`LibraryDrawerError.deletionDisabled`（`"删除功能暂未开放"`）拦截了 `deleteSampleDrawer` 与 `deleteBatchDrawer`。
- `Sources/SpinLabApp/App/RootSplitView.swift`（约第 197 行）：侧边栏右键菜单调用 `appState.library.deleteExistingDrawer(batchId:)`，目前只报未开放提示，不改任何文件。
- `Sources/SpinLabApp/App/LibraryMutationService.swift`、`LibraryFeatureStore+Facade.swift`、`LibraryFeatureStore+PreviewSync.swift`：保留 `deleteExistingDrawer` 入口，目前均走禁用分支。
- `Sources/SpinLabApp/Library/LibrarySyncService.swift`：`applyBatch` / `applyAll` 中原有 `deleteSampleDrawer` / `deleteBatchDrawer` 调用已被 `LibraryMutationSafetyGuard` 在写前拦截。
- `Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift`：`LibrarySample` 存放在各样品目录的 `sample.json` 中，尚未有软删除 / 废纸篓标记字段。

## 已定规则（用户 2026-11-17 拍板）

- **空样品判定**：无测量数据、无图、无手填参数（仅含基础建档信息）。
- **分级确认**：空样品直接进废纸篓；有数据样品弹二次确认；彻底删除 / 清空废纸篓弹不可逆确认。
- **保留策略**：永久保留，不自动清空。
- **存储与恢复**：采用 Zotero 式软删除标记，物理目录原地不动，恢复零冲突。
- **可见性与同步**：普通列表 / 搜索 / Workbench 隐藏；Registry 同步不复活、不物理删除。

## 我怎么验收（在测试 Library 里）

1. 新建一个空样品，点删除：无二次确认直接进入废纸篓；普通列表、搜索和 Workbench 选样里看不到它，在废纸篓视图里看得到。
2. 找一个带测量或图的样品，点删除：弹出二次确认；点取消不动，点确认后进入废纸篓，磁盘测量和图文件仍保留在原处。
3. 执行一次 Registry 同步：废纸篓里的样品既没有复活，磁盘文件也没有被删。
4. 在废纸篓里对有数据的样品点“还原”：样品回到原批次列表，测量和图完整可用。
5. 在废纸篓里点“彻底删除”：弹出不可逆二次确认，确认后样品从废纸篓消失，对应样品目录从磁盘删除。

## 开工

分支和 PR：从最新的 `main` 新建分支，第一次推送后开 PR。
流程：以 `taskType: "design"` 调用 `reviewloop_begin`，本文件全文作为 `contractText`（设计通过后再开实现）。

1. 先核对“代码现状”一节。与实际不符就停下来说明。
2. 设计时重点交代：废纸篓标记存放在哪里、空样品判定口径与代码依据、Registry 同步如何跳过/保护废纸篓样品、彻底删除时如何避免误删共享图表或索引竞争。
3. 实现后先跑定向测试，再跑完整测试和仓库收尾检查。
4. 在 PR 里把 `docs/V5_ROADMAP.md` 5.6.x 段对应的任务 9 勾上并写上 PR 编号。
5. 请用户按“我怎么验收”亲手走一遍。合并由用户决定。

## 任务 4 后续兼容说明（2026-11-23）

原任务 9 的空样品判断包括“有手填参数需二次确认”。任务 4 的新模型取消单独的 Manual Parameter：**已填写的 Sample Result Value 算作有科研数据**，进入废纸篓应二次确认；只在 Library Catalog 里存在但尚未填写的 Result Definition 空槽位不算样品数据。由任务 4 添加对应读取与测试；本说明不改变任务 9 已合并的 V1 删除实现和旧真实 Library。
