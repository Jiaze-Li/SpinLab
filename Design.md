# SP-PUBLISH-01 — Design v1.0

- **policy_sha:** `ff99b437c3d7117620c06d444d69adab2c4085a7`
- **Plan:** Plan.md v1.0（`25cd88f2`）+ PR 209 评论补充（用户在 Design 指令中明确要求纳入；见 §8 的 AC-09~AC-12，它们**只追加**，不改 AC-01~AC-08）
- **核查基线：** SpinLab `origin/main@e9455a40`（**比 Plan 基线 `d51c32c3` 新**；差异见 F-1）。Web Library 仓库未重新核查，沿用 Plan 记录。
- **目标 / 非目标：** 同 Plan §4、§6。本设计不新增产品能力。

## 0. 与 Plan 基线的差异（须用户知晓）

main 自 `d51c32c3` 起新增了「自动发布」（PR 208 系列）：保存 Rules Book 或 Library 索引变化后，5 秒防抖自动调用同一个发布。Plan 没有提到它，且 Plan §5 写「发布操作须明确由用户触发」。**本设计不删除它**（它是用户已合并的既有行为），见 Assumptions A-1，需用户确认。

## 1. 已核实事实（`origin/main@e9455a40`）

- **F-1 发布编排唯一入口在 AppState，且已有防重入：** `SpinLabAppState.swift:410` `func publishWebLibrary() { guard !libraryFeatureStore.webLibraryPublishState.isRunning else { return } …libraryFeatureStore.beginWebLibraryPublish()… publisher.publishWebLibrary(repoRootURL:) …finishWebLibraryPublish(exitCode:) / failWebLibraryPublish(summary:) …webLibraryAutoPublisher.publishFinished()`。
- **F-2 状态归 Library 的 store：** `LibraryFeatureStore.swift:56` `struct WebLibraryPublishState { … publishedSuccessfullyMessage = "Published successfully." … publishedSiteMessage = "Site: https://spinlab-web-library.pages.dev" … var isRunning, statusMessage, summaryMessage, outputLines, completedAt, presentationRevision }`；`:177` `var webLibraryPublishState`；转换函数在 `LibraryFeatureStore+Facade.swift:90-160`（`webLibraryPublishPresentation` 按退出码 + 输出文本判定：含 `No web snapshot changes` → 无变化，退出码 0 → 成功，否则失败）。
- **F-3 UI 在 Library 页：** `LibraryPrimaryView.swift:143` `Button("public to html") { state.viewModel.publishWebLibrary() }` 、`:147 .disabled(lib.webLibraryPublishState.isRunning)`、`:59 webLibraryPublishStatusView`、`:157` 状态/日志视图；`LibraryViewModel.swift:32` `func publishWebLibrary() { appState?.publishWebLibrary() }`。
- **F-4 自动发布也走同一入口：** `SpinLabAppState.swift:200` `webLibraryAutoPublisher = WebLibraryAutoPublisher(isPublishing: { …webLibraryPublishState.isRunning }, startPublish: { [weak self] in self?.publishWebLibrary() })`；`:401` `shouldAutoPublishAfterRulesSave(section:autoPublishEnabled:)`；`:405 requestWebLibraryPublishAfterLibraryChange()`；`SpinLabAppState+LibraryCoordination.swift:216` `applyExistingIndex` 调用它；`RootSplitView.swift:52` `appState.webLibraryAutoPublishEnabled = true`（仅真实窗口出现时打开，测试/预览不触发）。
- **F-5 执行服务：** `WebLibraryPublishService.swift:15-31` 只启动 `/bin/bash scripts/publish_web_library.sh`，逐行回传 stdout/stderr，返回退出码。测试 `V552WebLibraryPublishServiceTests.swift`、`V552WebLibraryPublishStateTests.swift`、`WebLibraryAutoPublisherTests.swift` 已用替身覆盖它。
- **F-6 脚本：** `scripts/publish_web_library.sh:19 library_root="/Users/jack/Downloads/data"`（硬编码）；依次 `export_static_library.py` → `validate_web_library.py` → `check_web_library_changes.py`（返回 0=无变化则 `exit 0`，1=有变化才继续）→ `git add public; git commit -m "Update SpinLab web snapshot"; git push`；日志前缀 `[publish-web] Exporting / Validating / Checking / Publishing…`，末尾 `Cloudflare Pages will redeploy automatically.`。脚本在 `d51c32c3` 与 main 上逐字相同。
- **F-7 导航：** `InteractionStateModels.swift:3 enum AppArea: String, CaseIterable, Identifiable, Codable { case inbox="Inbox"; case workbench="Workbench"; case library="Library" }`；`SpinLabSidebarMenuProvider.swift:9 AppArea.allCases.map`（图标、children 各有 `switch area`）；`AppRouter.swift:41 routePath(for:)` 与 `:~100 deepLink(for:)` 对 `AppRoutePath` 穷尽 switch；`SpinLabAppState+Navigation.swift:112 navigationRequiresDraftDecision`：`case .inbox, .workbench, .workbenchArea, .workbenchArchivedRecord, .workbenchWorkflow: return selectedArea == .library`（离开 Library 且有未保存 Drawer 草稿 → 先问）。
- **F-8 已有边界测试：** `PR3SampleWorkspaceSelectorTests.swift:107` 有 `["LibrarySettingsSectionView","RegistryWorkspaceSectionView","publishWebLibrary",…]` 列表（禁止在 Sample Workspace 选择器里出现发布相关词）。
- **F-9 网页模板存在运行时函数覆盖（评论补充 1）：** 脚本顺序 `index.html:90-93` 依次加载 `app.js`、`compare.js`、`compare-overview.js`、`compare-scope.js`（均带 `?v=__ASSET_VERSION__`，导出时由 `export_static_library.py:552 text.replace("__ASSET_VERSION__", web_asset_version(template_dir))` 替换）。后加载文件重新赋值先前函数，共 13 处：
  - `compare.js`（改写 app.js 的函数）：`:400 const renderLibrarySampleList = renderSampleList; :402 renderSampleList = function renderSampleListWithCompare()`、`:452 renderChartsNav =`、`:461 stepSelectedSample =`、`:518 renderMetadataPanel =`、`:632 attachEvents =`、`:675 reRender =`；
  - `compare-overview.js`（改写 compare.js 的函数）：`:5 compareOverviewOrder =`、`:7 renderCompareOverview =`、`:53 renderMetadata =`；
  - `compare-scope.js`（改写 compare.js 的函数）：`:20 rebuildCompareGroups =`、`:81 syncCompareChrome =`、`:106 renderCompareGroupList =`、`:132 attachEvents =`（第二次覆盖 attachEvents）。
- **F-10 缓存：** `Resources/WebLibraryTemplate/_headers`：`/*` 下 `Cache-Control: no-cache`；脚本地址版本由 F-9 的 `__ASSET_VERSION__` 替换产生（PR 210 已做）。
- **F-11 现有网页检查只看文件：** `validate_web_library.py:157 validate_frontend`（只查 chart.url 写法）与 `:177 validate_generated_ui_matches_templates`（产物 == 模板渲染结果）。没有任何在浏览器里运行页面的检查。
- **F-12 本机可用的无界面浏览器：** `/Applications/Google Chrome.app` 存在；没有 Playwright/Puppeteer。Chrome 的 `--headless --dump-dom` 可输出脚本执行后的 DOM，不需新依赖。

## 2. Options

| # | 路线 | 结论 |
|---|---|---|
| **A（采用）** | 新增 `AppArea.publish` + 一个小的 Publish 状态 store（接管 F-2 的状态与转换）+ `Features/Publish` 视图；编排函数（F-1）保留为 AppState 上**唯一**入口，自动发布仍调用它；Library 页删除按钮与状态视图；脚本与执行服务**不改语义**。 | 复用最多：路由/侧栏/防重入/自动发布/测试替身全部沿用，只有「状态与 UI 的归属」搬家。 |
| B | 只把按钮和状态视图从 Library 页挪到新页面，状态仍留在 Library 的 store。 | 否决：Library 仍是发布状态的持有者，不满足 AC-02/AC-06「无分叉、无双重业务负责人」。 |
| C | 新建独立 Swift Package（Publish 引擎 + UI），重写脚本为 Swift。 | 否决：违反 Plan §5 最小变更与「不预设新 Swift Package」；风险大于收益，且会改变 AC-03 的行为语义。 |

网页侧另比较：**W1（采用）** 在 `app.js` 中为 6 个被改写的函数开明确扩展点，`compare.js` 注册自己的实现；`compare-overview.js`/`compare-scope.js` 的实现并回 `compare.js` 的函数本体（它们本就同属对比功能）；**W2** 保持现状只给 renderSampleList 打补丁——否决（评论补充要求梳理全部覆盖点）；**W3** 合并成单文件打包器——否决（引入构建步骤）。

## 3. Assumptions（大白话；需用户划掉不成立的）

- **A-1** 「自动发布」（改规则/资料库后自动发到网站）是你有意保留的功能；本次整理**保留**它，只是在 Publish 页标明这次是「自动」还是「手动」触发。若你要求 Plan 里「必须手动触发」按最严格理解，请告诉我，我会改为只提示「有待发布的更改」。
- **A-2** 发布脚本里写死的资料库路径（`/Users/jack/Downloads/data`）**就是你现在实际使用的资料库**。本次不让 App 把「当前资料库路径」传给脚本，因为路径若不同会悄悄改变发布的数据范围。脚本只增加「环境变量可覆盖」的能力（默认值不变），供测试用临时目录。
- **A-3** 没有需要迁移的旧发布状态：状态只存在内存（F-2 无持久化），所以不做迁移。
- **A-4** 你的 Mac 装有 Google Chrome（F-12）。网页真实页面检查在没有 Chrome 的机器上标 `NOT RUN`，**不算通过**，也不阻止发布脚本继续（避免换机器后无法发布）；有 Chrome 时检查失败则阻止发布。
- **A-5** 线上（Cloudflare）是否部署完成，桌面端无法确认，Publish 页一律写「已推送到 GitHub，Cloudflare 部署未核实」，不去联网探测（探测属于新能力）。
- **A-6** 用旧版本 App 打开含「Publish」区域记录的界面状态文件时，旧版会忽略/回到默认区域；不做向下兼容处理。

## 4. 设计

### 4.1 App 侧（权威与依赖方向）

- **权威：** Library 数据仍只由 Library 持有；Publish store 只持有发布**任务状态**（内存）。依赖方向：`Features/Publish` 视图 → Publish store ← AppState 编排（唯一入口）→ `WebLibraryPublishingCapability`（执行服务）→ 脚本。Library 不再引用任何发布状态。Library 的变更继续通过 `requestWebLibraryPublishAfterLibraryChange()`（F-4）通知自动发布器；这是「Library → 请求」的单向通知，不持有状态。
- **状态模型（在 F-2 基础上最小扩展）：** 结果枚举：`idle / running / noChanges / pushedToRemote / failed(stage, summary)`；`trigger: manual | automatic`；`completedAt`。`pushedToRemote` 的文案固定为「已推送到 GitHub；Cloudflare 部署未核实」（取代 "Published successfully." + 站点地址的暗示，站点地址作为链接保留但标注「未核实」）。失败阶段由脚本既有日志前缀判定（最后出现的 `Exporting / Validating / Checking / Publishing`），退出码非 0 且无前缀时为 `failed(process)`；执行服务抛错为 `failed(launch)`。「无变化」判定沿用 F-2 的文本匹配，但抽成一个有单元测试的纯函数。
- **重复触发：** 保留 F-1 的 `isRunning` 守卫；手动按钮运行中禁用；自动触发在运行中被推迟到结束后（`WebLibraryAutoPublisher` 现有语义，不改）。
- **状态不因切页重置：** store 由 AppState 持有（与 Library store 同级），Publish 视图只读，切换区域不重建。
- **导航：** `AppArea` 增加 `publish`；`AppRoutePath` 增加 `.publish`（深链 `publish`）；`routePath(for:)`、侧栏（图标 + 空 children）、`AppPrimaryContent/AppDetailContent` 的分支补齐；`navigationRequiresDraftDecision` 的离开列表加入 `.publish`（返回 `selectedArea == .library`），因此**从有未保存草稿的 Library 进入 Publish 同样被拦截**，Publish 没有绕过捷径。Library 页不放跳转按钮（避免第二个入口语义）；用户从侧栏进入。
- **Library 页：** 删除 `public to html` 按钮、`webLibraryPublishStatusView`、`LibraryViewModel.publishWebLibrary`、`isWebLibraryPublishDetailsExpanded`；`PR3SampleWorkspaceSelectorTests` 的禁词列表继续有效。
- **不改：** 执行服务接口、`WebLibraryAutoPublisher`、脚本的导出/校验/变化检测/git 流程与退出码、Web-Tools、Web 仓库 `functions/api/*`。

### 4.2 脚本（AC-03）

只做两处向后兼容改动：`library_root="${SPINLAB_LIBRARY_ROOT:-/Users/jack/Downloads/data}"`（默认不变）；在 `validate` 之后、`check changes` 之前插入「网页真实页面检查」调用（见 4.3，A-4 的 NOT RUN 规则）。独立命令行入口 `scripts/publish_web_library.sh` 保持原样可用。

### 4.3 网页模板（评论补充 1–4 → AC-09~AC-12）

1. **扩展点：** `app.js` 暴露一个 `features` 注册表；其 6 个函数（`renderSampleList / renderChartsNav / stepSelectedSample / renderMetadataPanel / attachEvents / reRender`）在内部明确询问已注册的对比功能；`compare.js` 只注册、不再赋值给别处声明的函数。`compare-overview.js`、`compare-scope.js` 的 7 个覆盖（F-9）并入 `compare.js` 对应函数本体，两个文件要么删除要么只剩独立新函数（由 Worker 决定，`index.html` 与 `WEB_TEMPLATE_FILES` 同步）。**页面行为必须等价**（同样的 DOM 输出，见 AC-10）。
2. **静态护栏（零浏览器依赖）：** `validate_web_library.py` 增加检查：模板 JS 中不得出现对「在另一个文件/先前已声明的函数名」的重新赋值（如 `^\s*(renderSampleList|…)\s*=\s*function`；用函数声明名单自动推导，不手写列表）。
3. **真实页面检查：** 新脚本 `scripts/check_web_library_page.py`：用导出结果起本机临时静态服务，调 `Google Chrome --headless --dump-dom`（加 `--virtual-time-budget`）打开主页，断言：分组标题出现（按前缀分组，且**不是**平铺列表）、同步时间文字出现、新建样品入口出现；另用仅存在于 `scripts/tests` 的测试页加载同一份模板脚本并切到对比模式，断言对比分组列表出现、切回后分组列表恢复。找不到 Chrome → 输出 `NOT RUN: no headless browser` 并以专用退出码返回（脚本据 A-4 继续，但**不打印 PASS**）。
4. **版本与缓存保持：** 增加检查：导出后的 `index.html`、`new-sample.html` 中不存在字面量 `__ASSET_VERSION__`，所有本地脚本/样式地址带 `?v=<非空>`；同一模板两次导出值相同、改动任一模板文件内容后值不同；`_headers` 含 `Cache-Control: no-cache`。
5. **验收口径：** 网页改动的验收证据 = 一次真实 Chrome 无界面运行的 DOM 摘录（含上述断言）；只通过静态护栏不能标 PASS（AC-12）。

### 4.4 文档

更新 `docs/architecture/INDEX.md`（新增 Publish 区域及首读文件）、`docs/web_library.md`（扩展点约定：功能之间不得运行时替换函数）；不新增规划/账本文件。AGENTS.md 要求的检查（UI 规则、controls contract、版本守卫）在 Code 阶段按实际运行记录。

## 5. 不变量

- **I-1** 发布任务状态只有一个持有者（Publish store）；编排入口只有一个（AppState）；Library 与 Publish 视图均不得直接启动脚本。
- **I-2** 任何导航、预览、测试不会触发脚本；自动发布只在 `webLibraryAutoPublishEnabled`（真实窗口）时可触发（F-4）。
- **I-3** `pushedToRemote` 永不声称「已上线」；退出码 0 且含 `No web snapshot changes` 才是 `noChanges`。
- **I-4** Library 数据与 `_spinlab` 侧车文件只读；导出器的路径安全与校验关卡不变。
- **I-5** 模板中无函数在运行时被另一个文件重新赋值；扩展只通过 `features` 注册表。
- **I-6** `_headers` 的 no-cache 与脚本地址版本化不被任何发布流程丢弃。

## 6. 失败模式与证据

| 声明 | 可能的失效方式 | 能检出的证据 |
|---|---|---|
| 状态单一持有者 | Library 与 Publish 各留一份 | 单元测试：Library store 不含 publish 状态；`rg webLibraryPublish` 只在 Publish store/编排中出现 |
| 防重入 | 手动+自动并行 | 替身发布器：运行中再触发只执行 1 次；结束后补一次（沿用 `WebLibraryAutoPublisherTests`） |
| 状态真实 | 退出码 0 被显示为「已上线」 | 状态单元测试：成功→「Cloudflare 未核实」；无变化；失败各阶段（export/validate/git/process/launch） |
| 导航保护 | 带草稿进入 Publish 被放行 | 路由测试：dirty Drawer + `.publish` → 需要决定；无草稿 → 直接进入；Publish↔Library↔Workbench 往返选中态保持 |
| 旧入口兼容 | 脚本语义被改 | 脚本测试（临时 Library/临时 Web 仓库，`SPINLAB_LIBRARY_ROOT` 指向夹具，**不 push**：用本地 bare remote）：默认路径行为不变、无变化时退出 0 且输出既有文案 |
| 无函数覆盖 | 仍有后加载覆盖 | 静态护栏测试：夹具中故意放一个覆盖 → 检查失败；现有模板 → 通过 |
| 页面行为等价 | 重构后分组/对比模式变化 | Chrome 无界面 DOM 断言（正向：分组标题、同步时间、新建样品入口、对比列表；负向：平铺列表不出现） |
| 缓存保持 | 新流程丢了版本/headers | 导出结果断言（见 4.3-4） |
| 无 Chrome | 被误报 PASS | 检查输出 `NOT RUN` 且证据表标 NOT RUN |

## 7. 前提状态、最小实施顺序、授权草案

- **顺序：** ① 路由/侧栏/Publish store 与视图 + Library 页清理（含测试）→ ② 状态模型与文案 → ③ 脚本环境变量与脚本测试 → ④ 网页扩展点重构 → ⑤ 静态护栏 + 页面检查 + 版本/缓存检查 → ⑥ 文档与全套检查。网页（④⑤）与 App（①②）互不依赖，可顺序交付。
- **与 Sample-centred 任务：** 本设计不碰 Library 数据模型；共享点仅 `AppArea/AppRoutePath` 与 `LibraryFeatureStore` 的发布字段删除，Code 阶段开始前需重新对照当时 main。
- **授权草案（均需用户在 Code 阶段明确给出，当前一律未授权）：** 修改 App/脚本/模板/测试/文档；commit 与 push 到本任务分支；将 PR 设为 Ready；merge；任何真实的 `publish_web_library.sh` 运行（含 push）、Cloudflare 部署、线上数据操作、权限变更。检查只用临时目录与本地 bare remote。

## 8. Work Contract（Code 阶段直接使用本节）

**结果：** SpinLab 左侧出现与 Inbox/Library/Workbench 并列的 Publish；发布触发（手动与既有自动）、状态、失败原因、输出集中在 Publish；Library 页不再有发布按钮和状态；发布脚本与独立命令行入口行为不变；网页模板不再有运行时函数覆盖，且有真实页面检查。

**必需不变量：** I-1 ~ I-6（§5）。**边界：** 不新增产品能力（Plan §6）；不修改 Library 数据模型、Web-Tools、Web 仓库 `functions/api/*`、手机录入协议；不改脚本的导出/校验/变化检测/git 语义与退出码；不新增依赖或 Swift Package；不做真实发布/部署/push。

**验收标准：**
- **AC-01~AC-08：** 逐字同 Plan §7，并按 §4、§6 的方案落实（AC-02：旧按钮**删除**；AC-04 状态集合以 §4.1 为准；AC-07 证据表见 §6；AC-08 文档为 §4.4）。
- **AC-09｜模板无覆盖：** `Resources/WebLibraryTemplate/*.js` 中不存在对其它文件/先前已声明函数的运行时重新赋值（F-9 的 13 处全部消除）；扩展仅经 `features` 注册表；静态护栏对夹具中的覆盖报失败。
- **AC-10｜页面行为等价且被真实检查：** 在无界面 Chrome 中，导出页面显示按前缀分组标题、同步时间、新建样品入口；对比模式的分组列表出现且可切回；检查失败则 `publish_web_library.sh` 在 git 步骤前退出非 0。无 Chrome 时报告 `NOT RUN`（不得算 PASS，不阻止脚本）。
- **AC-11｜版本与缓存保持：** 导出的 HTML 内无 `__ASSET_VERSION__`、本地资源均带非空 `?v=`；内容变→版本变、内容不变→版本不变；`_headers` 含 `Cache-Control: no-cache`；有自动化检查。
- **AC-12｜网页验收证据口径：** 完成报告须附一次真实 Chrome 无界面运行的 DOM 断言输出；仅静态护栏/文件检查通过不得标网页验收 PASS。

**验证与证据：** Swift：`swift test` 中新增/调整的 Publish 状态、路由与导航保护、防重入（含自动发布）、Library 无发布状态测试；脚本：`scripts/tests` 新增的发布脚本夹具测试（临时 Library、本地 bare remote、环境变量路径）与模板护栏/版本缓存测试；页面：`check_web_library_page.py` 实际输出；仓库规定的 `check_ui_rules.sh`、controls contract、版本守卫按实际运行记录。**只有实际运行并记录结果的才标 PASS；未运行标 `NOT RUN` 并给出用户验收动作**（在 Mac 上打开 Publish 页做一次手动发布并核对 Cloudflare 站点，属于需用户另行授权的真实发布）。

**停止条件：** 需要改变 Plan 验收标准、发布权限/公开范围、Library 数据权威，或用户对 A-1/A-2 的回答与默认前提冲突 → 停下回报用户；`HUMAN_REQUIRED` 立即停止；完成后停在本地 PASS，不 merge、不部署。
