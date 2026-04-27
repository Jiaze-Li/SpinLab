# v5.3.6 Plot Shell 曲线拖拽排序 — 实施 Handoff

> 状态：实施方案已收敛。Claude 方稿 + Codex 方稿对抗评审完成，本文件为最终落地方案。
> 来源：`tmp/2026-04-27-5.3.6-shell-curve-drag-claude.md` + `tmp/2026-04-27-5.3.6-shell-curve-drag-codex.md`（已归档）

## 0. 验收契约

实施完成后用户应能：

1. 在 3ω R(1ω) 和 R(3ω) 两张 stacked 图上，按住一条曲线向 y 方向拖动 → 释放后该曲线出现在虚线落点对应的视觉 y 位置。
2. 拖动过程中显示一条横跨 plot 宽度的水平虚线（dash [5,3]），y 跟随鼠标、x 锁死。
3. 释放后整张图重排：被拖曲线落到新位置，其他曲线按视觉 y 重新计算 stack offset，PNG 重渲染。
4. legend 行顺序自动跟随曲线视觉顺序（top → bottom）。
5. legend 卡片位置（用户拖整块 legend）保持现状能力。
6. 用户拖动 legend 区域时走 legend 整块拖动（保留现状），不会误触发曲线重排。
7. Save Pack → Load Pack 后，曲线顺序恢复；中途修改分析参数重新 Analyze 后，旧顺序里仍存在的 series 保留位置，新增 series 追加到末尾。
8. 在 stacked 图右键 → "Reset Curve Order" 恢复 workflow 默认顺序（3ω 是温度升序）；非 stacked 图（RAHE/Hc/RT/Scaling）该菜单项置灰。
9. RAHE / Hc / RT / Scaling 等非 stacked 图的画布拖动行为零变化（不响应曲线拖）。
10. 旧 AnalysisPack 加载行为零变化（无 `seriesOrder` 字段时按 workflow 默认顺序渲染）。

## 1. 数据模型变更

### 1.1 `TabRenderState`（`Workbench/V3/TabRenderManager.swift`）

新增字段：

```swift
struct TabRenderState: Codable, Hashable, Sendable {
    var legendPoint: CGPointCodable?
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    var seriesLabelOverrides: [Int: String] = [:]
    var hiddenPointLabelIndicesBySeries: [Int: [Int]] = [:]
    var seriesOrder: [String]? = nil   // ★ 新增：bottom-to-top sample id 数组
}
```

语义：
- `nil` = 未手动排序，使用 workflow 默认顺序。
- 非空数组 = 该 tab 唯一排序真相，bottom → top。
- 元素 = `WorkbenchPlotSeries.sampleID`。**禁止**用 series index、温度、角度、label、sourceRef 当 key。

Codable migration：
- `CodingKeys` 加 `.seriesOrder`。
- `init(from:)` 用 `decodeIfPresent([String].self, forKey: .seriesOrder)`，缺字段 → nil。
- `init(...)` 加默认参数 `seriesOrder: [String]? = nil`。

### 1.2 `WorkbenchPlotSeries`（`Workbench/V3/WorkbenchResultContracts.swift`）

新增字段：

```swift
struct WorkbenchPlotSeries: Hashable, Sendable {
    var label: String
    var x: [Double]
    var y: [Double]
    var sourceRef: String?
    var sampleID: String?       // ★ 新增：稳定 series 身份
    var renderMode: SeriesRenderMode
    var pointLabels: [String]
    var lineWidth: Double
    var renderModeLocked: Bool
    var metadata: [String: String]
}
```

Codable backward-compatible：
- `CodingKeys` 加 `.sampleID`。
- `decodeIfPresent(String.self, forKey: .sampleID)`。
- `encodeIfPresent(sampleID, forKey: .sampleID)`。
- 所有 init 加默认参数 `sampleID: String? = nil`。

**禁止**把 sample id 塞进 `metadata`（污染 LegendDimensionResolver 输入空间）。**禁止**用 `sourceRef`（路径会因导入位置 / 文件移动变化，不是身份）。

### 1.3 `WorkbenchPlotPayload`（同文件）

新增 opt-in 字段：

```swift
struct WorkbenchPlotPayload: Codable, Hashable, Sendable {
    // …existing fields…
    var reverseSeriesForLegend: Bool
    var seriesReorderable: Bool = false   // ★ 新增：opt-in 拖拽排序
}
```

Codable：`decodeIfPresent(Bool.self, forKey: .seriesReorderable) ?? false`。

只有 workflow renderer 显式设 `true`，canvas 才允许曲线拖。其他 payload 行为零变化。

### 1.4 `ThreeOmegaFieldSweepResult` 增加 sampleID

文件：`Workbench/V3/ThreeOmegaIngestionContracts.swift`（如果该 struct 在别处定义则改对应文件）。

```swift
struct ThreeOmegaFieldSweepResult: Codable, ... {
    // …existing fields (temperatureK / hField / r1omega / r3omega / sampleMetadata / ...)…
    var sampleID: String?    // ★ 新增；从 WorkflowMeasurementSearchHit.sampleKey 注入
}
```

注入点：在 ingestion / store 构造 field sweep 时（具体路径由实施方在代码里 trace），把对应 search hit 的 `sampleKey` 写入。Codable backward-compatible（`decodeIfPresent`）。

### 1.5 `reverseSeriesForLegend` 处置

**决定：保留，不合并、不弃用。**

- 它是 payload 层 legend 展示策略（"legend top = visual top"），workflow renderer 在构造 payload 时定。
- `seriesOrder` 是 tab 状态层视觉堆叠真相（"bottom → top"），shell 用户运行时定。
- 两者关注点不同，合并会让 `seriesOrder` 既表堆叠又表 legend 行顺序，产生双义。

求值顺序见 §2.2。

3ω `renderR1omega` / `renderR3omega` 现有 `reverseSeriesForLegend: true` 保持不动；XY Rotation 同样保持现状（本轮不 opt-in 拖拽，等 sampleID 注入链路验证后单独打开）。

## 2. 渲染管线变更

### 2.1 `WorkbenchRenderPipeline.Input` 加字段

```swift
struct Input: Sendable {
    // …existing…
    var legendPoint: CGPoint?
    var seriesOrder: [String]? = nil   // ★ 新增
}
```

### 2.2 `render(_:)` 求值顺序

```
step 2  styleParams patch + legendPoint 写入（保持）
step 3  display-only overrides（保持）
step 4  render mode 应用（保持）
step 4a ★ 新：若 payload.seriesReorderable && input.seriesOrder != nil
            检查 payload.series 当前顺序（按 sampleID 比对）是否与 input.seriesOrder 一致；
            不一致 → 加 pipelineWarnings 一条（不修，让上游 renderer 暴露漏排错误）
step 4b reverseSeriesForLegend 反转（保持）
step 4c legend dimension auto-resolve（保持）
step 5  chartStyleOverrides merge（保持）
step 6  parse chart style（保持）
step 7  resolve renderer options（保持）
step 8  compute layout（保持）
step 9  apply seriesLabelOverrides（保持）
step 10 render PNG（保持）
step 11 manifest payload restore axisMapping（保持）
step 12 attach warnings（保持）
```

**关键决定（v5.3.6 修订 2026-04-27）**：pipeline **不**做兜底重排。原因是 stacked 图的 series.y 已经在 renderer 内含 stack offset；如果 pipeline 真的重排数组顺序而不重算 offset，会产生"legend 顺序与视觉位置正确，但每条曲线 y 高度按旧顺序"的静默错配——比"没有兜底"更危险。Pipeline 的职责改为"检测错排 + 报警"，让 renderer 漏排错误显式可见，而不是被静默掩盖。

`reverseSeriesForLegend` 是纯 series 数组反转、不涉及 y 重算，所以保持现状。

### 2.3 顺序一致性检测实现

```swift
private static func detectSeriesOrderMismatch(
    _ series: [WorkbenchPlotSeries],
    expected: [String]
) -> String? {
    let actual = series.compactMap(\.sampleID)
    let expectedFiltered = expected.filter { id in actual.contains(id) }
    let actualFiltered = actual.filter { id in expected.contains(id) }
    guard expectedFiltered != actualFiltered else { return nil }
    return "seriesOrder mismatch: renderer produced \(actualFiltered) but expected \(expectedFiltered). " +
           "stack offsets are likely incorrect — fix the renderer to honor input.seriesOrder."
}
```

调用点：step 4a 仅当 `payload.seriesReorderable && input.seriesOrder != nil` 时跑此检测，结果非 nil 时进 `pipelineWarnings`。Renderer 自身漏排是 bug，pipeline 不修复、只暴露。

## 3. Workflow Renderer 改动（3ω）

文件：`UseCases/ThreeOmegaPlotRenderer.swift`

`renderR1omega` / `renderR3omega` 新签名（增加可选 `seriesOrder` 输入 + 接受外部 align 后的顺序）：

```swift
mutating func renderR1omega(
    sweeps: [ThreeOmegaFieldSweepResult],
    device: String,
    seriesOrder: [String]? = nil      // ★ 新增
) -> (Data?, WorkbenchPlotLayout?) {
    guard !sweeps.isEmpty else { return (nil, nil) }

    // 1. 按 seriesOrder 重排 sweeps（已 align 过 — align 在 store 层调用）
    let orderedSweeps: [ThreeOmegaFieldSweepResult] = {
        guard let order = seriesOrder, !order.isEmpty else { return sweeps }
        let bySampleID = Dictionary(uniqueKeysWithValues: sweeps.compactMap { sweep in
            sweep.sampleID.map { ($0, sweep) }
        })
        var result: [ThreeOmegaFieldSweepResult] = []
        var consumed: Set<String> = []
        for id in order {
            if let s = bySampleID[id] { result.append(s); consumed.insert(id) }
        }
        for sweep in sweeps where sweep.sampleID.map({ !consumed.contains($0) }) ?? true {
            result.append(sweep)
        }
        return result
    }()

    // 2. 按重排后的顺序重算 stack offset
    let offsets = ThreeOmegaStackOffsetUseCase().execute(
        yValues: orderedSweeps.map { $0.r1omega },
        multiplier: stackOffsetMultiplier,
        minGapFraction: minGapFraction
    )

    // 3. 构造 series（携带 sampleID）
    let series = zip(orderedSweeps, offsets).map { (sweep, offset) in
        WorkbenchPlotSeries(
            label: _tempLabel(sweep.temperatureK),
            x: sweep.hField.map { $0 / 10000 },
            y: sweep.r1omega.map { $0 + offset },
            sampleID: sweep.sampleID,                  // ★ 携带
            metadata: sweep.sampleMetadata ?? [:]
        )
    }

    var payload = WorkbenchPlotPayload(
        workflowID: "3w",
        workflowDisplayName: "3w",
        title: _defaultTitle("R(1ω)", device: device),
        axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
        series: series,
        reverseSeriesForLegend: true,
        seriesReorderable: true                        // ★ opt-in
    )
    return _render(payload: &payload, options: _stackedOptions(sweepCount: sweeps.count))
}
```

`renderR3omega` 同 pattern。

`renderRAHE1omegaVsT` / `renderRAHE3omegaVsT` / `renderHcVsT` / `renderRT` / `renderScaling` **不**改 —— `seriesReorderable` 默认 false，行为零变化。

XYRotationPlotRenderer 本轮**不**改（保持现状）。

## 4. Align 算法（重新 Analyze 时对齐旧顺序）

调用点：`ThreeOmegaWorkspaceStore` 在重新 Analyze / pack restore / rerender 触发 renderR1omega 之前。

```swift
/// 对齐旧 seriesOrder 与当前 sweep 集合。
/// 返回对齐后的 order；若 old 为 nil 或对齐结果与 default 完全相同，返回 nil（让默认顺序生效）。
func alignSeriesOrder(old: [String]?, defaultIDs: [String]) -> [String]? {
    guard let old, !old.isEmpty else { return nil }
    let currentSet = Set(defaultIDs)
    var seen: Set<String> = []
    var kept: [String] = []
    for id in old where currentSet.contains(id) && seen.insert(id).inserted {
        kept.append(id)
    }
    let keptSet = Set(kept)
    var result = kept
    // 新增 id 按 default 顺序追加到末尾（产品契约 5：新增位置不重要）
    for id in defaultIDs where !keptSet.contains(id) {
        result.append(id)
    }
    return result == defaultIDs ? nil : result
}
```

调用 pattern（store 层）：

```swift
let defaultIDs = sweeps.compactMap(\.sampleID)
let aligned = alignSeriesOrder(
    old: tabs.state(for: tab).seriesOrder,
    defaultIDs: defaultIDs
)
if aligned != tabs.state(for: tab).seriesOrder {
    tabs.tabStates[tab, default: TabRenderState()].seriesOrder = aligned
}
let (data, layout) = renderer.renderR1omega(sweeps: sweeps, device: device, seriesOrder: aligned)
```

## 5. seriesLabelOverrides index 重映射（避免 label 跑到错误曲线）

**问题**：`seriesLabelOverrides: [Int: String]` 是 series-index → label。重排后 index 漂移，用户改过的 legend label 会贴到别的曲线。

**本任务范围内的解法（窄）**：在 store 层调用 renderR1omega 之前，按"旧 index → sampleID → 新 index"做一次性重映射：

```swift
/// 把 [oldIndex: label] 按当前 sweeps 顺序重映射到 [newIndex: label]。
/// 调用前提：旧 layout 的 series 数组顺序已知（保存到 tabState 时一并存的 sampleID 顺序）。
/// 简化方案：在每次 render 前，根据当前 series sampleID 顺序，把 label override 也按 sampleID 重 key 一次。
func remapSeriesLabelOverrides(
    oldOverrides: [Int: String],
    oldSampleIDs: [String?],   // 上次渲染时各 index 的 sampleID
    newSampleIDs: [String?]    // 本次渲染时各 index 的 sampleID
) -> [Int: String] {
    var byID: [String: String] = [:]
    for (oldIdx, label) in oldOverrides {
        if oldIdx < oldSampleIDs.count, let id = oldSampleIDs[oldIdx] {
            byID[id] = label
        }
    }
    var result: [Int: String] = [:]
    for (newIdx, idOpt) in newSampleIDs.enumerated() {
        if let id = idOpt, let label = byID[id] { result[newIdx] = label }
    }
    return result
}
```

`TabRenderManager` 加内部缓存 `lastRenderedSampleIDs[Tab: [String?]]`（@ObservationIgnored，不持久化）。每次 render 完更新；下次 render 前把 `seriesLabelOverrides` 按缓存重映射后再传给 pipeline。

`hiddenPointLabelIndicesBySeries` 同样问题，同样处置。R1/R3 stacked line 当前没有 point labels，影响低；先按相同 pattern 处理保持一致。

**长期债**：`seriesLabelOverrides` / `hiddenPointLabelIndicesBySeries` 的 key 类型迁移到 `[String: ...]`（sampleID-keyed）是独立任务，不在 v5.3.6 范围。

## 6. Shell 交互机制

### 6.1 `WorkbenchPlotCanvas` API 变更

```swift
struct WorkbenchPlotCanvas: View {
    // …existing…
    var seriesReorderable: Bool = false                        // ★ 新增
    var currentSeriesOrder: [String]? = nil                    // ★ 新增（用于 Reset 按钮置灰判定）
    var onSeriesOrderCommit: (([String]) -> Void)? = nil       // ★ 新增
    var onResetSeriesOrder: (() -> Void)? = nil                // ★ 新增
}
```

预留但**不**接的字段（实时让位升级时启用）：
- `var onSeriesOrderPreview: (([String]?) -> Void)? = nil` —— 状态机里保留 preview 分支但首版不调用。

### 6.2 DragGesture 状态机

新增内部状态：

```swift
private enum DragMode: Equatable {
    case none
    case legend       // 沿用现有 legend 整块拖动
    case series(sampleID: String, originalOrder: [String])
}
@State private var dragMode: DragMode = .none
@State private var seriesGuideYScreen: CGFloat? = nil   // y-locked guide 当前屏幕 y
```

替换现有 `simultaneousGesture(DragGesture(...))`：

```
onChanged 第一帧（dragMode == .none）：
    1. 判定 startLocation 是否落在 layout.legendRows.map(\.hitRect) 转 screen 后的 union 内：
        命中 → dragMode = .legend，复用现有 legend onChanged 逻辑
    2. 否则若 seriesReorderable && layout 可用：
        a. startLocation 必须在 plotRect screen 映射内（plot 外不响应）
        b. 调 hitTestSeries(...) 找命中的 series
        c. 命中且该 series 有 sampleID → dragMode = .series(sampleID, currentSeriesOrder ?? defaultOrder)
    3. 否则 → dragMode = .none，本次 drag 不响应

onChanged 后续帧：
    .legend  → 现有逻辑
    .series  → 更新 seriesGuideYScreen = value.location.y（锁 y，忽略 x）
    .none    → 不响应

onEnded：
    .legend  → callback onLegendDrag(finalNorm)，清状态
    .series  → 计算 newOrder（§6.4），callback onSeriesOrderCommit(newOrder)，清状态
    .none    → 清状态
```

**mid-drag 不允许切换分支**——dragMode 只在第一帧定，之后不再判。

### 6.3 曲线 hit-test

判定带：**8pt** screen-space 半径（Apple HIG 推荐最小命中区域 ~8pt）。

实现位置：`WorkbenchPlotLayout` 加扩展方法（不新建独立 helper 文件，避免范围爆炸；如实施中复用度高再拆出 `WorkbenchPlotInteractionHitTester.swift`）：

```swift
extension WorkbenchPlotLayout {
    /// 在屏幕空间对所有 reorderable series 做 hit-test。
    /// 返回距离 startLocation 最近且 ≤ 8pt 的 series sampleID 和它在该 x 处的视觉 screen y。
    func hitTestSeries(
        location: CGPoint,
        fittedRect: CGRect,
        payload: WorkbenchPlotPayload,
        radius: CGFloat = 8
    ) -> (sampleID: String, screenY: CGFloat)? {
        // 1. 对每个 series 取 polyline (x,y) 数据
        // 2. 数据→screen 用与 renderer 一致的 axis extent + plotRect 映射
        //    （注意 reverseSeriesForLegend 已经在 pipeline reverse 过 series 数组，
        //     hit-test 输入的是 reverse 后的顺序——但 series 自带 sampleID，
        //     不依赖 index，无歧义）
        // 3. 对每条 polyline 计算 location 到每段线段的最短距离
        // 4. 取距离 ≤ radius 的候选；多条接近时取距离最小者；
        //    距离相同取 |startLocation.y - polyline.midY| 最小者
        // 5. 没命中 → nil；命中 → (series.sampleID, polyline 中段对应 screen y)
    }
}
```

实施注意：
- 必须复用 renderer 的 axis extent / padding 逻辑，否则曲线命中位置和视觉线条偏移。建议把 axis extent 计算从 `WorkbenchChartRenderer` 抽到一个共享 helper，hit-test 和 renderer 都用。
- 没有 `sampleID` 的 series 不参与 hit-test。
- 若 reorderable payload 中**任何**可见 series 缺 sampleID，canvas 应禁用曲线拖（报 warning），避免部分曲线可拖部分不可拖造成混乱。

### 6.4 释放时映射到 newOrder

```swift
func computeNewOrder(
    draggedSampleID: String,
    guideYScreen: CGFloat,
    currentSeries: [WorkbenchPlotSeries],
    layout: WorkbenchPlotLayout,
    fittedRect: CGRect
) -> [String] {
    // 1. 取所有可排序 series（sampleID != nil）当前的视觉中心 y（polyline 中点 screen y）
    let pairs: [(id: String, y: CGFloat)] = currentSeries.compactMap { s in
        guard let id = s.sampleID else { return nil }
        let yScreen = computeSeriesMidScreenY(s, layout: layout, fittedRect: fittedRect)
        return (id, id == draggedSampleID ? guideYScreen : yScreen)
    }
    // 2. 按视觉 y 升序：屏幕 y 大 = bottom（plotRect 在 SwiftUI 是上小下大）
    //    bottom→top order 等价于 screen y 从大到小
    let sortedTopDown = pairs.sorted { $0.y < $1.y }       // top → bottom（screen y 升序）
    // 3. seriesOrder 语义是 bottom → top，所以反转
    return sortedTopDown.reversed().map(\.id)
}
```

**未决（U1，等实施实测）**：曲线视觉 y 取 polyline 中点 y 还是 plotRect.midX 处的 y。本设计选 polyline 中点 y（更直观），实施时如发现非均匀采样导致中点偏离用户感知，改为 plotRect.midX 处的 y。

### 6.5 Y-locked dashed guide

```swift
@ViewBuilder
private var seriesDragGuidePreview: some View {
    if case .series = dragMode, let yScreen = seriesGuideYScreen {
        let fitted = fittedRect(in: canvasSize)
        // plotRect screen 映射边界
        let plotMinX = /* layout.plotRect.minX → screen x */
        let plotMaxX = /* layout.plotRect.maxX → screen x */
        Path { p in
            p.move(to: CGPoint(x: plotMinX, y: yScreen))
            p.addLine(to: CGPoint(x: plotMaxX, y: yScreen))
        }
        .stroke(
            Color.accentColor.opacity(0.85),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
        )
    }
}
```

风格与现有 `legendDragPreview` 一致（同 dash、同色）。

加到 `body` 的 overlay 链中（与 `legendDragPreview` 同级）。

### 6.6 hover popover 与 drag 共存

实施注意（Codex 风险点）：拖动期间 `hoverPopover` 不应被触发或不应遮挡 dashed guide。两种处置（任选）：
- 在 `dragMode != .none` 时禁用 hoverPopover（最干净）。
- 在 SwiftUI overlay 顺序里把 dashed guide 放在 popover 之上（z-order 更高）。

推荐前者。

## 7. 右键 Reset Curve Order

`WorkbenchPlotCanvas.contextMenu` 改：

```swift
.contextMenu {
    Menu("Copy PNG") { /* 现有 */ }
    if onResetSeriesOrder != nil {
        Divider()
        Button("Reset Curve Order") { onResetSeriesOrder?() }
            .disabled(!seriesReorderable || currentSeriesOrder == nil)
    }
}
```

置灰条件：
- `seriesReorderable == false`，**或**
- `currentSeriesOrder == nil`（用户未拖过、当前正用默认顺序）。

动作：`onResetSeriesOrder` → store 调 `tabs.resetSeriesOrder()` → `tabState.seriesOrder = nil` → rerender。**不**影响 legendPoint / label overrides / font / style overrides。

接受 SwiftUI 限制：`.contextMenu` 不能按落点区分曲线 / legend / 空白，全画布右键都看到此菜单项；置灰条件已覆盖非 stacked 场景。

## 8. opt-in 启用范围（v5.3.6）

| 图 | seriesReorderable |
|---|---|
| 3ω `fieldSweep1omega`（R(1ω) vs H stacked） | **true** |
| 3ω `fieldSweep3omega`（R(3ω) vs H stacked） | **true** |
| 3ω RAHE(1ω) vs T / RAHE(3ω) vs T | false |
| 3ω Hc vs T / RT / Scaling | false |
| XY Rotation 全部 tab | false（本轮不启用，等 sampleID 注入链路验证后单独打开） |

`WorkflowWorkspaceShell` 从 store 读 active tab 的 manifest payload，把 `seriesReorderable` / `currentSeriesOrder` / commit 与 reset callback 透传给 `WorkbenchPlotCanvas`。

## 9. TabRenderManager 新接口

```swift
final class TabRenderManager<Tab: Hashable & Sendable> {
    // …existing…

    func updateSeriesOrder(_ order: [String]?) {
        if let order, !order.isEmpty {
            tabStates[activeTab, default: TabRenderState()].seriesOrder = order
        } else {
            tabStates[activeTab, default: TabRenderState()].seriesOrder = nil
        }
    }

    func resetSeriesOrder() {
        tabStates[activeTab]?.seriesOrder = nil
    }

    /// ★ 关键修订：clearStates 必须保留 seriesOrder（同 legendPoint，是 canvas preference）
    func clearStates() {
        for tab in tabStates.keys {
            let preserved = tabStates[tab]
            tabStates[tab] = TabRenderState(
                legendPoint: preserved?.legendPoint,
                seriesOrder: preserved?.seriesOrder
            )
        }
    }
}
```

## 10. 持久化路径全链

写入：
1. Canvas `onSeriesOrderCommit(newOrder)` →
2. `WorkflowWorkspaceShell` → `store.updateSeriesOrder(order)` →
3. `tabs.updateSeriesOrder(order)` 写入 active tab 的 `TabRenderState.seriesOrder` →
4. store 触发 active tab rerender →
5. Save Pack：`_buildPackConfig()` 已调 `tabs.snapshotStates(...)`；`seriesOrder` 自动随 `TabRenderState` 进 `ThreeOmegaPackConfig.tabStates` →
6. `AnalysisPack.config = encode(ThreeOmegaPackConfig)`。**envelope 不改。**

读取：
1. Load Pack decode `ThreeOmegaPackConfig` →
2. `TabRenderState` decode 缺字段 = nil →
3. `tabs.restoreStates(config.tabStates, ...)` →
4. store rerender 各 tab，调用 align（§4）→ 调用 renderR1omega/renderR3omega 时传入 aligned order。

需加 `decodeIfPresent` 默认的 Codable 节点：
- `TabRenderState.seriesOrder`
- `WorkbenchPlotSeries.sampleID`
- `WorkbenchPlotPayload.seriesReorderable`
- `ThreeOmegaFieldSweepResult.sampleID`

## 11. 实时让位 — **本轮不做**

首版只做"y-locked 虚线 guide + 释放重排"。

不做实时让位的原因：
- CoreGraphics PNG pipeline 每帧 100ms 级延迟，拖动中不可接受。
- `ThreeOmegaStackOffsetUseCase` 本身 O(n) 便宜，瓶颈是 PNG render + layout。
- 让位实现需要 polyline ghost overlay 或 chart renderer 改造，超出本任务范围。

升级路径（v5.3.7+ 候选，**不**列入本任务）：
- canvas overlay 层临时移动曲线（用 SwiftUI Path + offset），不重渲染 PNG。
- 或引入 vector/GPU 绘制层。
- 或 `onChanged` 节流到 6-10 Hz，仅在 series.count ≤ 12 时启用，并自动降级机制。

## 12. 改动文件清单

| 层 | 文件 | 改动 |
|---|---|---|
| Domain / Contracts | `Workbench/V3/WorkbenchResultContracts.swift` | `WorkbenchPlotSeries.sampleID`、`WorkbenchPlotPayload.seriesReorderable`、Codable migration |
| Domain / Contracts | `Workbench/V3/ThreeOmegaIngestionContracts.swift`（确认实际位置） | `ThreeOmegaFieldSweepResult.sampleID`、Codable backward-compatible |
| Repository / Pack | `Workbench/V3/TabRenderManager.swift` | `TabRenderState.seriesOrder`、Codable、`updateSeriesOrder` / `resetSeriesOrder`、`clearStates` 保留 seriesOrder、`buildPipelineInput` 透传 |
| Repository / Pack | `Workbench/V3/ThreeOmegaPackContracts.swift` | 不改顶层字段；仅测试旧 config decode |
| Pipeline | `Workbench/V3/WorkbenchRenderPipeline.swift` | `Input.seriesOrder`、step 4a 兜底重排 |
| Pipeline / Geometry | `Workbench/V3/WorkbenchPlotLayout.swift` | 加 `hitTestSeries(...)` 扩展；如 axis extent 计算需要从 renderer 抽出共享，加共享 helper |
| UseCase / Renderer | `UseCases/ThreeOmegaPlotRenderer.swift` | `renderR1omega` / `renderR3omega` 加 `seriesOrder` 入参、按顺序重排 sweeps + 重跑 stack offset、series 携带 sampleID、payload `seriesReorderable: true` |
| UseCase | `UseCases/ThreeOmegaStackOffsetUseCase.swift` | **不改**（算法本身正确） |
| Workflow Store | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | (a) field sweep 构造时注入 sampleID（从 search hit）；(b) rerender 前调 align；(c) 调 renderer 时传 aligned order；(d) `seriesLabelOverrides` 重映射；(e) 加 `updateSeriesOrder` / `resetSeriesOrder` 公开方法 |
| Workflow Provider | `Features/Workbench/WorkflowWorkspaceProvider.swift` | `WorkbenchPlottingStore` / `WorkbenchWorkspaceProviding` 加 `activeSeriesOrder`、`canReorderSeries`、`updateSeriesOrder`、`resetSeriesOrder` |
| Shell | `Features/Workbench/WorkflowWorkspaceShell.swift` | 把 `seriesReorderable` / `currentSeriesOrder` / commit / reset callback 透传给 `WorkbenchPlotCanvas` |
| Canvas UI | `Features/Workbench/WorkbenchPlotCanvas.swift` | DragGesture 状态机重写、加 `seriesDragGuidePreview`、contextMenu 加 Reset Curve Order、新 prop / callback |
| Workflow View | `Features/Workbench/ThreeOmegaWorkspaceView.swift` | 把新 callback 接到 store mutator |
| Tests（新增） | `Tests/SpinLabAppTests/V536CurveDragOrderTests.swift` | 见 §13 |

预计改动行数：~700–900 行，跨 ~9 个文件。中等改动。

## 13. 测试要求

`Tests/SpinLabAppTests/V536CurveDragOrderTests.swift` 必须含：

1. **Codable migration**：旧 `TabRenderState` JSON（无 seriesOrder）/ 旧 `WorkbenchPlotSeries` JSON（无 sampleID）/ 旧 `WorkbenchPlotPayload` JSON（无 seriesReorderable）解码后行为与 v5.3.5 相同。
2. **opt-in off**：`payload.seriesReorderable = false` 时 pipeline 既不检测也不报警（即使 input.seriesOrder 非 nil）；行为零变化。
3. **opt-in on + 无 seriesOrder**：行为与 v5.3.5 完全相同（特别是 `reverseSeriesForLegend` 仍生效）；pipeline 不报警。
4. **opt-in on + 有 seriesOrder + renderer 已正确排好**：pipeline 检测通过、`pipelineWarnings` 不含 mismatch 条目；legend 顺序 = 视觉 top → bottom。
4b. **opt-in on + 有 seriesOrder + renderer 漏排**：pipeline 检测到 mismatch，向 `pipelineWarnings` 写入一条含 expected / actual 对照的诊断信息；series 数组保持 renderer 原样不被 pipeline 修改（避免静默掩盖 stack offset 错配）。
5. **align 算法**：
   - 旧 order 全部存在 → 保持
   - 新增 id → 追加末尾
   - 消失 id → 剔除
   - 旧 order = nil → 返回 nil（让默认）
   - 旧 order 与 default 完全相同 → 返回 nil
6. **R1/R3 offset 重算**：用两组 sweeps（amplitude 不同）测试重排后 offset 与"按新顺序输入 stack offset use case"结果一致。
7. **Canvas hit-test**：8pt 内命中、近者优先、相邻曲线优先级、plot 外不响应、缺 sampleID 不响应。
8. **seriesLabelOverrides 重映射**：用户改过 series A 的 label，重排后 label 仍贴在 series A（按 sampleID）。
9. **Pack save / load**：写入 seriesOrder → 序列化 → 反序列化 → seriesOrder 恢复。
10. **clearStates 保留 seriesOrder**：调用后 legendPoint 和 seriesOrder 都还在。

参考现有测试 pattern（`V*RulesConfigContractTests.swift` / `V*Tests.swift`）。

## 14. 已知风险与未决

| 编号 | 描述 | 处置 |
|---|---|---|
| R1 | sampleID 注入链路：3ω `ThreeOmegaFieldSweepResult` 当前未带 sampleKey，需从 search hit 注入 | 实施时先 trace ingestion → field sweep 构造路径，确认 `WorkflowMeasurementSearchHit.sampleKey` 可达；如发现一个 sample 对应多条 sweep（罕见），用复合 id `"\(sampleKey)#\(sweep.id)"` |
| R2 | hit-test axis extent 一致性 | 必须复用 renderer 同源逻辑；如发现 chart renderer 内嵌不易复用，把 axis extent 抽到 `WorkbenchPlotAxisExtent`-style 共享 helper，hit-test 和 renderer 都调 |
| R3 | seriesLabelOverrides / hiddenPointLabelIndicesBySeries 长期债 | 本任务用 sampleID 重映射保正确性；key 类型迁移到 `[String: ...]` 列入 v5.4.x+ 独立任务，**不**进 v5.3.6 |
| R4 | hover popover 与 drag guide z-order / 触发冲突 | 实施时在 `dragMode != .none` 时禁用 hoverPopover |
| R5 | contextMenu 不能按落点区分 | 接受现状，"Reset Curve Order" 全画布显示，置灰条件覆盖非 stacked |
| R6 | reorderable payload 部分 series 缺 sampleID | canvas 禁用曲线拖（warning 一条），不允许部分可拖部分不可 |
| U1 | 曲线视觉 y 取 polyline 中点 y 还是 plotRect.midX 处的 y | 默认 polyline 中点 y；实施时若用户感知偏离，改为 midX y。两套都低成本 |
| U2 | seriesOrder 含 id 但 payload 不含 | pipeline step 4a 静默丢弃 + warning 一条 |

## 15. 实施顺序建议

按 layered architecture 分层推进，每层落地后跑 build：

1. **Domain / Contracts 层**（§1.1–1.4）：加字段 + Codable migration + 测试 case 1。
2. **Pipeline 层**（§2）：加 `Input.seriesOrder` + step 4a + 测试 case 2/3/4。
3. **align 算法**（§4）：纯函数，单测 + 测试 case 5。
4. **Workflow Renderer 层**（§3）：renderR1omega / renderR3omega 改 + 测试 case 6。
5. **Workflow Store 层**（§5、§9、§10）：sampleID 注入、align 调用、label 重映射、updateSeriesOrder / resetSeriesOrder。
6. **Provider / Shell 层**（§8、§12 中 Shell）：透传 callback 和 props。
7. **Canvas UI 层**（§6、§7）：DragGesture 状态机、hit-test 扩展、guide overlay、contextMenu。测试 case 7、case 8 通过 hit-test 单测 + 一次性手动验证（无 UI 自动化）。
8. **Workflow View 层**（§12 中 View）：callback 接线。
9. **集成测试**（§13 case 9/10）+ 手动 UAT（按 §0 验收契约 1-10 逐条试）。

每层完成后跑 `swift build`（具体命令见 `~/.claude/CLAUDE.md` workflow.md §5）。**不要**跨层并行改动。
