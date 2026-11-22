# 任务 3：同一个 Library 只允许一个 SpinLab 可写

很小，独立一个 PR。前置：无。

## 目标

万一同时开了两个 SpinLab 指向同一个 Library，第二个只能看、不能改。

## 需求

1. 我正常只开一个 SpinLab：一切照旧，没有任何多出来的提示。
2. 我又开了第二个 SpinLab，指向同一个 Library：它提示"这个 Library 已在另一个 SpinLab 中打开，当前为只读"，能浏览，所有写入操作被拒绝。
3. 第一个 SpinLab 退出或崩溃后，再开一个：正常可写，不需要我手动清理什么。
4. 换一个 Library：新 Library 可写，旧 Library 的占用被释放。

## 不做

- 多台电脑之间、网盘同步之间的互斥。
- 两个 SpinLab 同时写的协调与合并。
- G1-01 补充设计 v0.1–v0.4 里的任何机制。

## 代码现状（`main`，Agent 开工前须自行复核）

- `main` 上没有任何进程间的锁或单实例检查；在 `Sources` 里搜索 `flock`、`NSFileCoordinator`、`LSMultipleInstancesProhibited` 均无结果。
- PR #195 的分支也没有加锁；它的安全检查只在写入前做只读判断。
- Library 的写入由主线程上的 `LibraryFeatureStore` 同步发起，经 `LibraryMutationService`、`LibrarySyncService` 到 `LibraryStore`。
- 本任务是执行包里唯一允许新增锁的任务，依据是需求 2；锁只有这一把。
- 现有 Library 写入并非全部只经过 `LibraryMutationService`：还要核对 Inbox 的 `LibraryWriteTransaction`、Workbench 图/结果保存、Registry 同步、手机拾取、备份和永久删除等入口，避免第二实例仅禁用“新建 Sample”，却仍能修改同一 Library。
- `LegacySampleBackfillService` 当前存在单次 UID 补发使用的临时锁；须核对与新进程级 Library 锁共存时不会死锁或错误地拒绝同一进程操作。

## 实现提示

- 打开 Library 时对一个锁文件取独占锁，整个进程存活期间持有；取不到就进入只读。进程退出时操作系统自动释放，所以不需要清理逻辑。
- 锁文件放在 Library 文件夹之外（例如 Application Support 下），这样"只读打开"不会在 Library 里留下任何文件。
- 锁按 Library 的**真实位置**区分：先把路径解析成实际目录（消除符号链接和别名）再取锁，不要直接用用户给的路径字符串。同一个文件夹通过两条不同路径打开，必须争用同一把锁。
- 只读状态在正式写入边界统一拦截，不要只在每个按钮上各自判断；若有多个现成持久化入口，设计一个可复用的写许可守卫并核实所有 Library 写入调用点，避免漏掉非 UI / 异步路径。
- 根目录首次打开和切换时先完成真实路径解析及锁状态评估，不能因拿不到锁仍调用创建目录、索引重建、修改时间戳等写入动作；只读情况下允许纯读取，缺损或不可读库应按 K13 报错。
- 只读提示形式（已定）：窗口顶部一条常驻横幅，文案即需求 2 那句；不用弹窗。
- 从只读恢复可写：不做自动重试，用户重新打开 Library 或重启 SpinLab 时才重新取锁。
- `LegacySampleBackfillService` 的一次性锁保持不动；若与进程级锁确有冲突，停下来告诉用户，不要自行合并或替换。
- 锁文件名由规范化真实路径派生（如哈希），测试须证明不同 Library 互不阻塞。
- 当前任务只保护**同一台机器、同一个 Library 的两个 SpinLab 进程**，并不扩展到多用户协作或多电脑同步。

## 我怎么验收

1. 只开一个 SpinLab，新建一个测试样品，成功。
2. 不关它，用终端再开一个（`open -n /Applications/SpinLab.app`）。第二个出现只读提示，新建样品被拒绝。
3. 关掉第一个，在第二个里重新打开 Library（或重启它），新建样品成功。

Agent 另需用自动测试证明：同一个 Library 文件夹经符号链接路径打开时，第二个实例同样是只读。定向测试还需覆盖：竞争锁失败时不产生 Library 写入；切换 Library 释放旧锁；持锁进程正常退出/崩溃后可重新取得锁；锁竞争下 Inbox 导入、Workbench 保存、Registry Apply、样品创建/编辑/删除等代表性写路径全部被拒绝。若其中某一类入口在测试中未覆盖，必须明确报告，而不能声称“所有写入已保护”。

## 开工

分支和 PR：使用任务 3 的 Draft PR（从 `main` 建立独立分支）；代码、定向测试和 Roadmap 完成勾选在同一 PR 收尾。
流程：以 `taskType: "code"` 调用 `reviewloop_begin`，本文件全文作为 `contractText`，`SKELETON.md` 的 K1–K13 作为 `constraints`。

1. 先核对"代码现状"一节。与实际不符，或"已定的做法"会破坏旧样品的读取，就停下来告诉用户，不要自己换方案。
2. 实现，先跑相关的定向测试，最后跑完整测试和仓库规定的收尾检查。
3. 推送，等评审机器人。
4. 在 PR 里把 `docs/V5_ROADMAP.md` 5.6.x 段对应的那一行勾上并写上 PR 编号。
5. 请用户按"我怎么验收"亲手走一遍。合并由用户决定。

不要加本文件和 `SKELETON.md` 都没提到的机制（锁、日志、重试、新的状态）。觉得必须加，先停下来说明是哪条需求需要它。
