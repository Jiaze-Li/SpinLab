# SP-PUBLISH-01 — SpinLab Publish 模块独立化与架构整理

> **Document:** Plan.md · v1.0 · 2026-11-15  
> **Phase:** Plan（完成需求收敛；尚未进入 Design，未获设计/实施批准）  
> **Repository:** `Jiaze-Li/SpinLab`  
> **Task branch:** `docs/plan-publish-module-consolidation`（Draft PR；不以 PR 状态代表任何审查通过）  
> **policy_sha:** `ff99b437c3d7117620c06d444d69adab2c4085a7`（`personal-skills/engineering-lead/skill.md` v1.1.0；同一任务后续阶段继续按此 SHA 读取相应 Skill）  
> **Read-only repository baseline:** SpinLab `main@d51c32c3bdbab3e1965343d4e06f850298d64484`；SpinLab-Web-Library `main@569e3d280a7b9139597b1ba4837907f4a88e198d`  
> **Authority:** 本 Plan 的全文是本任务的需求依据；PR 中的 Plan Brief 仅为摘要。进入 Design 后，不得用 Brief 或未审查的设计假设替代本 Plan。若实质需求发生变化，应先由用户确认 Plan 修订。

## 1. 真实问题与目标

SpinLab 已有可用的 Web Library 发布能力，但发布入口、任务状态、执行服务和跨仓库脚本散落在 Library 管理界面、App 全局状态、脚本与 Web 资源中。现有功能作为 Library 的附属操作存在，缺少清晰的独立产品管理入口、单一业务负责人和可维护的模块边界。随着 SpinLab 扩展，这会增加跨模块耦合、重复实现和发布误操作的风险。

**本任务不重新开发 Publish。** 要把现有发布能力整理为 SpinLab 的正式、集中管理的 Publish 一级功能区，并确定 Swift 管理层、共享基础设施、Python/Shell 出口、Web 模板与部署目标之间的职责及稳定接口。最终应当保留已有行为、便于维护与后续扩展，而不是追求移动文件或增加抽象的数量。

## 2. 用户、场景与失败代价

- **主要用户：** 当前单用户科研工作流中的 SpinLab 所有者；在 macOS 上组织 Sample、图表及其他已存成果，并将 Web Library 发布到现有网站。
- **常见操作：** 从 SpinLab 找到发布入口，查看当前/最近一次任务状态，明确执行一次发布，观察成功、无变化或错误，定位需要采取的下一步。
- **失败代价：** 误发布未打算传播的科研数据、导出错误内容、将尚未完成的云端部署显示为已上线、发布脚本失效、破坏已有 Web 浏览及手机数据录入、或因状态散落而难以定位故障。尤其不能让整理动作修改原始科研数据。

## 3. 已核实的当前基线（仓库静态事实，非运行 PASS）

1. `Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift` 目前包含 `public to html` 按钮，调用 `state.viewModel.publishWebLibrary()`，并展示发布状态和输出日志。
2. `Sources/SpinLabApp/App/SpinLabAppState.swift` 的 `publishWebLibrary()` 调用注入的 `webLibraryPublisher`，将输出/完成情况写入 `LibraryFeatureStore`；`Sources/SpinLabApp/App/State/LibraryFeatureStore.swift` 保存 `webLibraryPublishState`。
3. `Sources/SpinLabApp/App/WebLibraryPublishService.swift` 通过 `/bin/bash` 调用 `scripts/publish_web_library.sh` 并返回退出码、传递 stdout/stderr。
4. 现有 `scripts/publish_web_library.sh` 依次导出、验证、检测变化，必要时向 `SpinLab-Web-Library` 提交/推送静态 `public/`；网站由 Cloudflare Pages 后续部署。该脚本当前包含本机 Library 路径，路径配置与错误处理是否应调整须在 Design 检查，不在 Plan 预定实现。
5. Web Library 的 HTML/CSS/JS **唯一源码**在 SpinLab 的 `Resources/WebLibraryTemplate/`；`SpinLab-Web-Library/public/` 是可重新生成的发布产物。现有 `docs/ecosystem.md` 与 `docs/web_library.md` 已明确三仓库职责及发布数据流。
6. `SpinLab-Web-Library/functions/api/samples.js` 负责手机提交 Sample 的云端待接收记录，`functions/api/note.js` 管理网页 Notes，二者与静态发布有关联但不是导出器职责。
7. `Sources/SpinLabApp/App/SpinLabSidebarMenuProvider.swift`、`App/State/AppRouter.swift`、`AppPrimaryContent.swift`、`AppDetailContent.swift` 共同组成当前三个一级区域的导航与内容路由。
8. 仓库 `AGENTS.md` 规定跨区域更改先查 `docs/architecture/INDEX.md`，UI 变更遵循 `specs/04_UI_RULES.md`，修改代码后执行规定检查，并对文档/CI-only PR 使用 `no-release` 标签处理版本守卫。

上述仅为本次 Plan 的只读核查范围；未在真实 macOS 环境执行发布、构建、Cloudflare 部署或端到端测试。Design 必须补足其实施所需的调用链与消费者检查。

## 4. 要交付的结果（需求范围）

1. **独立的产品入口：** 左侧导航新增与 Inbox、Library、Workbench 同级的 Publish；在该入口内集中查看/控制已有 Web Library 发布过程。不是打开 HTML 文件的临时按钮，也不是整个网页的内嵌编辑器。
2. **单一管理职责：** Publish 拥有发布管理流程、当前及最近一次操作状态、错误呈现和用户触发入口。Library 继续拥有本地科研数据、Sample/Chart 等事实与存储；不得因 Publish 独立化出现第二份科研数据权威。
3. **清晰的代码与文件归属：** 明确 Web 发布 UI、状态、编排、可复用执行能力、导出/校验脚本、HTML 模板和目标仓库各自的 owner、输入输出及依赖方向；必要的搬迁仅以收敛职责和去除无用重复为准。
4. **兼容现有发布链：** 从本地 Library 生成静态快照 → 校验 → Git 发布 → Cloudflare Pages 部署的现有链路继续可用，现有 Web Library 页面、Sample/Chart 展示及既有 API 能力不受本次整理影响。
5. **工程可验收：** 为导航、任务状态、错误/无变化、脚本接入、区域隔离等真实行为提供可检查证据，修订恰当的架构入口文档，不引入多余平行说明或独立进度账本。

本 Plan 固定产品结果，**不预先规定**必须建立哪个 Swift Package、指定全部文件的新路径、状态具体类型、UI 组件树或重写现有脚本的技术方式；这些比较与细节属于 Design。

## 5. 不可突破的约束

- **数据权威：** Library 本地科研数据仍是 Sample 和已保存分析结果的权威。Publish 只能选择/读取并形成可发布的投影，不得改变原始测量、参数、分析算法、科研判断或 Library 的存储语义。
- **最小变更：** 优先复用已有发布机制和既有 App 路由、UI、依赖注入与测试扩展点；不以“大重构”或删文件数量作为完成条件。不能为了集中管理而新建无价值的抽象。
- **发布安全：** 保留导出器的路径安全与校验关卡，不绕过校验、不在普通界面导航/测试时触发真正的 Git push 或云端部署；失败不能标作成功。发布操作须明确由用户触发。
- **状态真实性：** 区分本地导出成功、远端 Git 推送成功与 Cloudflare 实际部署可访问；未知线上状态必须标为未知，不能据本地退出码推断线上已经部署。
- **独立系统边界：** 保留 SpinLab / SpinLab-Web-Library / SpinLab-Web-Tools 的职责区分；Web Library 模板源码和生成产物仍分别管理，Web-Tools 不是桌面 Publish 的部署目标。
- **既有用户流程：** 手机 New Sample 接入、云端 Notes 与现有 Web Access 入口不得无意中受到破坏或被改造成 Publish 的发布状态源。不可借本任务添加或修改线上权限。
- **路由兼容：** 用户从 Library 未保存编辑离开时，必须继续遵守现有导航保护；不要增加能绕过保护的 Publish 捷径。
- **全流程授权：** Plan / Design / Code 各自停步；未经另行明确授权不实施代码、不合并 PR、不部署、不删除数据或更改权限。

## 6. 明确不做的事

- 不新增“按 Sample/Chart 选择发布”“发布草稿/审核”“多站点发布”“发布历史/回滚”“公开分享权限”“可视化网页编辑器”等产品能力。
- 不重新实现或替换现有 Web Library HTML/CSS/JS；不将网站整体改写为 SwiftUI，也不把三个仓库合并。
- 不对 Library 数据模型、科研分析、文件导入流程、Web Tools 产品或手机录入协议做功能重构。
- 不新增云端账号、凭据、CI 权限、Cloudflare 配置、生产数据库迁移、服务部署或真实内容发布。
- 不借本任务清理不相关的技术债、修复不相关问题或建立第二份项目进度与架构事实来源。

## 7. 全局验收标准（AC）

**AC-01｜一级导航可用。** macOS App 的左侧存在可直接打开的 Publish 一级区域，与 Inbox、Library、Workbench 并列；在 Publish 与其他区域之间往返正常，选择状态与必要的未保存修改保护不回归。

**AC-02｜集中管理。** 现有 Web Library 发布的触发、进度/任务状态、失败原因和必要输出统一在 Publish 管理；Library 不再持有另一套能独立执行业务、与 Publish 状态分叉的发布控制流程。旧按钮可移除或仅导航到 Publish，具体交互由 Design 决定。

**AC-03｜行为兼容。** 在等价的本地 Library 输入、规则配置与 Web 模板下，Publish 仍使用同一业务发布语义：生成既有 Web Library 格式，保持必要验证，检测无变化并按既有目标发布。不得悄悄增删发布的数据范围；已有脚本的独立入口继续可用，或在设计中提供行为等价且有验证证据的兼容入口。

**AC-04｜状态与失败准确。** 成功、无变化、验证失败、进程执行失败、Git 操作失败及外部部署状态未知时有可辨识反馈；用户不能被错误告知“云端已经上线”；重复触发不会产生无意并行的同一发布任务。状态不因切换 Publish 视图而错误重置；不强制新增持久发布历史。

**AC-05｜科研数据和 Web 侧不受损。** 对本地权威数据只读，不更改 Sample/Measurement/Chart 的内容和身份；原有 Web Library 浏览功能以及手机 New Sample、Notes 接口保持兼容。本次重构不触碰 Web-Tools 的独立开发与部署关系。

**AC-06｜归属可解释且无双重权威。** Design 和最终代码/架构文档能明确说明 Publish 管理、Library 数据、共享执行能力、Shell/Python 导出、Web 模板与生成目标分别由谁维护；对比改前/改后的调用链，证明没有多套发布入口状态、互相循环调用或无实际用途的新层。

**AC-07｜验证可复现。** 有覆盖导航/离开编辑态、成功/无变化/失败/重复触发、已有发布脚本入口、导出校验、Web API 非回归的针对性测试与适当检查记录。只有实际运行且记录结果的检查才能标 PASS；无法在当前环境执行的云端和 macOS 实际验证须标明 `NOT RUN` 并给出用户验收动作。

**AC-08｜文档和收尾准确。** 更新现有项目文档的最小必要部分以体现新增一级区域和发布边界，不增加重复的长期规划/技术债文件；完成阶段报告给出受影响范围、真实 HEAD、测试/审查状态以及仓库 `AGENTS.md` 要求的构建/发布动作检查结果（不代表获准真实部署）。

## 8. 预期验证路径（不预先指定实现）

- **静态核查：** 追踪入口到发布脚本、Library 数据读取和 Web 模板产物的完整调用链，核实唯一业务负责人、依赖方向与未保存编辑保护。
- **有替身的自动测试：** 模拟发布器的退出码、输出、无变化和错误；验证应用状态不会误报、重复启动、切页面丢失；运行相关 Swift/脚本测试与 UI 规则检查。
- **隔离的导出检验：** 使用受控临时数据目录/输出目录验证导出结果及验证器，不触及正式 Library 数据、不执行真实 Git push。
- **需要额外许可的验收：** 真正发布到 Cloudflare、验证在线部署或改变 Web 生产数据属于额外独立授权；在未获授权时只做非生产证据并明确保留这一验收缺口。
- **阶段关卡：** Design 必须由独立 ReviewLoop Reviewer 按完整 Plan 检查；Code 后由现有 ReviewLoop 与 PR bot/CI 检查。不要把 Plan 文档提交等同于上述关卡通过。

## 9. 依赖状态与待查事实

| 前提/依赖 | 当前状态 | 对后续的要求 |
| --- | --- | --- |
| 现有 Publish 触发、状态、执行服务 | **静态代码已确认存在** | Design 按同一基线审计所有调用者和相关测试 |
| 静态网页模板与独立 Web Library 仓库 | **静态仓库事实已确认** | 维持既有单一模板源码和部署目标 |
| 一级 App 路由与 UI 约束 | **静态代码及规范已确认** | Design 核查未保存编辑与 UI 规则；Code 实测 |
| 发布脚本的实际运行环境、路径/凭据、容错 | **未知，需只读审计** | 不用猜测替代现有行为；明确可验证的兼容条件 |
| 云端发布结果及当前可访问性 | **未运行验证** | 不以 Git 推送或代码阅读伪称实际部署 PASS |
| 与正在进行的 Sample-centred 任务是否有具体修改冲突 | **待 Design 核查** | 仅在真实共享点有冲突时协调；本任务不碰数据权威合同 |

## 10. 已确认决定与保留的决策点

**已确认：**
- 已有 Publish 功能，本任务是架构与管理整理，不是从零建设。
- Publish 作为 SpinLab 左侧一级区域，管理独立，与 Inbox、Library、Workbench 并列。
- 保持原有 Web Library 能力和三仓库边界，以最小必要改动整理可维护的模块结构。
- 本轮只做 Plan，下一阶段必须由用户明确说 `Design`；Design 通过后仍需明确说 `Code`。

**尚未确认，留到 Design 比较/审计：**
- Publish UI、管理状态、执行服务最合适的具体代码目录与依赖注入方式；不预设新 Swift Package。
- 现有 Library 发布按钮是删除还是变为跳转 Publish 的入口；必须满足 AC-02。
- 当前脚本固定 Library 路径应如何与用户实际配置衔接，在不改变现有结果的前提下处理。
- 是否有真实需要迁移的旧状态/配置，以及如何兼容；未知时不编造迁移计划。
- 线上部署状态无法直接确认时的精确 UI 文案/状态来源。技术上无法验证的状态不可被假定为成功。

新增发布权限、扩大对外公开范围、改变科研权威或改变现有云端数据接入流程等重大产品决定，必须回到用户确认，不能在 Design/Code 中静默确定。

## 11. 本任务授权记录（按操作拆分）

| 操作 | 本轮授权边界 |
| --- | --- |
| 只读核查 SpinLab、Web Library 和 `personal-skills` | 已授权 |
| 新增本任务 `Plan.md` 与 Draft PR 的 Plan Brief | 已授权（用户本轮明确要求） |
| 新建仅用于此 Plan 的任务分支、提交并在远端保存 Plan 文档 | 仅限交付本轮用户明确要求的 Draft PR + Plan.md；不扩大到设计/产品代码 |
| 创建一个 Draft PR，保持 Draft 状态 | 已授权（用户本轮明确要求） |
| 进入 Design、创建/提交 Design 文件 | **未授权**；等待用户说 `Design`，并按后续约定确认仓库写权限 |
| 修改 App/网站/脚本/测试、commit 或 push 实现 | **未授权**；等待 `Code` 阶段及对应具体授权 |
| 将 PR 标为 Ready、合并、发布网站、部署 App | **未授权** |
| 删除/迁移正式科研数据、修改权限或凭据、破坏性操作 | **未授权** |
| 发布线上内容、触发实际 `publish_web_library.sh` | **未授权** |

**权限解释：** 本轮只交付 Plan 文档与 Draft PR；为实现该明确请求，任务分支上的 Plan 文档可通过 GitHub 文档写入操作形成提交。任何后续实现、合并和部署均不得由此推定授权。

## 12. 阶段与停止点

`Plan（当前） → 停 → 用户说 Design → 完整 Design（Options、Assumptions、已核实事实、Work Contract；ReviewLoop 独立审查） → 停 → 用户说 Code → 受限实施/审查 → 停 → 用户验收并自行决定后续操作`

**Plan 完成定义：** 本文可供完整需求审查，Draft PR 含清晰 Brief 与本文固定引用；未声称 Design/Code 已完成或已通过审查。下一步只有在用户明确发出 `Design` 后，才进入技术路线比较和设计关卡。
