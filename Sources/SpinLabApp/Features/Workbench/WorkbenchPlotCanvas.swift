import SwiftUI
import AppKit

// MARK: - WorkbenchPlotCanvas

/// 通用图像显示组件。
/// 有数据时显示渲染好的 PNG，无数据时显示占位符。
/// 支持：拖动重置 legend 位置、点击行内编辑 title / 轴标签 / legend 标签。
///
/// ## 自定义提示
/// - `minHeight` 控制最小显示高度
/// - 占位符图标和文字可按需修改
struct WorkbenchPlotCanvas: View {
    let imageData: Data?
    /// Layout from the most recent render. Nil = hit-testing and editing disabled.
    var layout: WorkbenchPlotLayout? = nil
    /// Current series label overrides keyed by sampleID (or Int-string for no-identity workflows).
    var seriesLabelOverrides: [String: String] = [:]

    /// Called with a plotRect-normalized point (x,y ∈ [0,1], y=0 bottom, y=1 top)
    /// when the user finishes a drag over the plot area. Nil = drag disabled.
    var onLegendDrag: ((CGPoint) -> Void)? = nil
    /// Inline edit callbacks — nil means that element is not editable.
    var onEditTitle:       ((String) -> Void)?               = nil
    var onEditXLabel:      ((String) -> Void)?               = nil
    var onEditYLabel:      ((String) -> Void)?               = nil
    /// (key, newLabel) — key is sampleID or Int-string fallback
    var onEditLegendLabel: ((String, String) -> Void)?       = nil
    /// Font size change callback: (styleParamsKey, newSize). Triggers re-render.
    var onFontSizeChange:  ((String, CGFloat) -> Void)?      = nil
    /// Point-dot toggle callback: (key, pointIndex) — key is sampleID or Int-string fallback.
    var onTogglePointLabelVisibility: ((String, Int) -> Void)? = nil
    /// Copy PNG at a given pixel scale; returns PNG data or nil if unavailable.
    var onCopyPNG: ((CGFloat) -> Data?)? = nil
    /// Style override change callback: (styleParamsKey, stringValue). Triggers re-render.
    var onStyleOverrideChange: ((String, String) -> Void)?   = nil
    /// Current chart style overrides — used to show current font size / tick density in edit panel.
    var chartStyleOverrides: [String: String] = [:]

    /// Related charts for hover popover (nil or empty = no popover).
    var relatedCharts: [WorkbenchResultReference]? = nil
    /// Library root for loading chart thumbnails.
    var libraryRootURL: URL? = nil

    // MARK: Series reordering (opt-in)
    var seriesReorderable: Bool = false
    var currentSeriesOrder: [String]? = nil
    /// Manifest payload for the active chart; required for series hit-testing.
    var seriesPayload: WorkbenchPlotPayload? = nil
    /// Called with bottom-to-top sampleID array when user commits a drag reorder.
    var onSeriesOrderCommit: (([String]) -> Void)? = nil
    /// Called when user selects "Reset Curve Order" from context menu.
    var onResetSeriesOrder: (() -> Void)? = nil

    // TODO(用户设计): 调整最小高度、背景样式、空状态文字
    var minHeight: CGFloat = 360

    @State private var canvasSize: CGSize = .zero
    /// Screen-space point of an in-progress drag (nil when not dragging).
    @State private var dragPreviewPt: CGPoint? = nil
    /// Normalized offset (plot-space, Y-up) from legend origin to cursor at drag start.
    /// Captured on the first onChanged frame; nil = not dragging.
    @State private var dragGrabOffsetNorm: CGSize? = nil
    /// Last valid adjusted normalized point during an active drag.
    /// Used by onEnded as fallback when cursor lands in padding area (plotNormalized → nil).
    @State private var lastValidDragNorm: CGPoint? = nil

    // Series drag state
    private enum DragMode: Equatable {
        case none
        case legend
        case series(sampleID: String)
    }
    @State private var dragMode: DragMode = .none
    @State private var seriesGuideYScreen: CGFloat? = nil
    /// Which chart element is currently being edited.
    @State private var editingElement: EditTarget? = nil
    /// Live text for the active edit field.
    @State private var editText: String = ""
    /// Screen-space rect of the element being edited, used to position the edit panel.
    @State private var editTargetScreenRect: CGRect = .zero
    /// Pixel size of the current rendered PNG used for coordinate conversion.
    /// Falls back to 800x600 until image metadata is available.
    @State private var rendererPixelSize: CGSize = CGSize(width: 800, height: 600)
    // Related charts hover popover state is managed by HoverPopoverModifier.

    private static let defaultRendererSize = CGSize(width: 800, height: 600)
    static let copyPNGScales: [CGFloat] = [1, 2, 3]

    private enum EditTarget: Equatable {
        case title
        case xLabel
        case yLabel
        case legend(key: String, originalLabel: String)
        case xTickLabel
        case yTickLabel
        case pointLabel(seriesIndex: Int, pointIndex: Int)
        case pointDot(seriesIndex: Int, pointIndex: Int)
    }

    /// The styleParams key for the font size of the currently editing element.
    private var editFontSizeKey: String? {
        switch editingElement {
        case .title:       return "titleFontSize"
        case .xLabel:      return "axisTitleFontSize"
        case .yLabel:      return "axisTitleFontSize"
        case .legend:        return "legendFontSize"
        case .xTickLabel:         return "tickLabelFontSize"
        case .yTickLabel:         return "tickLabelFontSize"
        case .pointLabel:         return "pointLabelFontSize"
        case .pointDot:           return nil
        case nil:                 return nil
        }
    }

    private static let fontSizeOptions: [CGFloat] = [12, 14, 16, 18, 19, 20, 22, 24, 25, 28, 32]

    /// The styleParams key for tick density of the currently editing element (nil if not a tick element).
    private var editTickDensityKey: String? {
        switch editingElement {
        case .xTickLabel: return "tickTargetX"
        case .yTickLabel: return "tickTargetY"
        default:          return nil
        }
    }

    var body: some View {
        if let data = imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(
                    GeometryReader { geo in
                        Color.clear.task(id: geo.size) { canvasSize = geo.size }
                    }
                )
                .overlay { legendDragPreview }
                .overlay { seriesDragGuidePreview }
                .overlay {
                    if let elem = editingElement {
                        editPanel(for: elem)
                    }
                }
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    // AppKit-level mouse handler: bypasses SwiftUI gesture system blocked by NSScrollView.
                    PlotCanvasMouseTracker(
                        isEnabled: editingElement == nil,
                        onTap: { handleTap(at: $0) },
                        onDragChanged: { start, current in
                            let fitted = fittedRect(in: canvasSize)
                            if dragMode == .none {
                                if seriesReorderable {
                                    if _isInLegendArea(start, fittedRect: fitted) {
                                        guard onLegendDrag != nil else { return }
                                        dragMode = .legend
                                    } else if let l = layout, let p = seriesPayload {
                                        let plotSR = WorkbenchPlotLayout.cgToScreen(
                                            l.plotRect, fittedIn: fitted,
                                            rendererWidth: l.rendererSize.width,
                                            rendererHeight: l.rendererSize.height
                                        )
                                        if plotSR.contains(start) {
                                            let allHaveSampleID = p.series.allSatisfy { $0.sampleID != nil }
                                            if allHaveSampleID,
                                               let hit = l.hitTestSeries(location: start, fittedRect: fitted, payload: p, radius: 8) {
                                                dragMode = .series(sampleID: hit.sampleID)
                                            }
                                        }
                                        if case .none = dragMode { return }
                                    } else { return }
                                } else {
                                    guard onLegendDrag != nil else { return }
                                    dragMode = .legend
                                }
                            }
                            switch dragMode {
                            case .none: return
                            case .legend:
                                guard let cursorNorm = plotNormalized(location: current, fittedRect: fitted) else { return }
                                if dragGrabOffsetNorm == nil {
                                    let startNorm = plotNormalized(location: start, fittedRect: fitted) ?? cursorNorm
                                    let origin = currentLegendOriginNorm()
                                    dragGrabOffsetNorm = CGSize(
                                        width:  startNorm.x - origin.x,
                                        height: startNorm.y - origin.y
                                    )
                                }
                                let grab = dragGrabOffsetNorm ?? .zero
                                let adjusted = CGPoint(
                                    x: min(max(cursorNorm.x - grab.width,  0), 1),
                                    y: min(max(cursorNorm.y - grab.height, 0), 1)
                                )
                                lastValidDragNorm = adjusted
                                dragPreviewPt = legendScreenOrigin(normalized: adjusted, fittedRect: fitted)
                            case .series:
                                seriesGuideYScreen = current.y
                            }
                        },
                        onDragEnded: { _, _ in
                            switch dragMode {
                            case .none: break
                            case .legend:
                                let last = lastValidDragNorm
                                dragPreviewPt      = nil
                                dragGrabOffsetNorm = nil
                                lastValidDragNorm  = nil
                                if let callback = onLegendDrag, let finalNorm = last {
                                    callback(finalNorm)
                                }
                            case .series(let sampleID):
                                if let p = seriesPayload, let l = layout, let guideY = seriesGuideYScreen {
                                    let fitted = fittedRect(in: canvasSize)
                                    let newOrder = _computeNewSeriesOrder(
                                        draggedSampleID: sampleID, guideYScreen: guideY,
                                        payload: p, layout: l, fittedRect: fitted
                                    )
                                    onSeriesOrderCommit?(newOrder)
                                }
                                seriesGuideYScreen = nil
                            }
                            dragMode = .none
                        }
                    )
                }
                .onAppear {
                    rendererPixelSize = Self.extractRendererPixelSize(from: nsImage) ?? Self.defaultRendererSize
                }
                .onChange(of: imageData) { _, _ in
                    rendererPixelSize = Self.extractRendererPixelSize(from: nsImage) ?? Self.defaultRendererSize
                }
                .contextMenu {
                    Menu("Copy PNG") {
                        ForEach(Self.copyPNGScales, id: \.self) { s in
                            Button("\(Int(s))x") {
                                let scaled = onCopyPNG?(s)
                                guard let d = scaled ?? imageData else { return }
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setData(d, forType: .png)
                            }
                        }
                    }
                    if onResetSeriesOrder != nil {
                        Divider()
                        Button("Reset Curve Order") { onResetSeriesOrder?() }
                            .disabled(!seriesReorderable || currentSeriesOrder == nil)
                    }
                }
                .hoverPopover(
                    showDelay: .seconds(1),
                    dismissDelay: .milliseconds(500),
                    arrowEdge: .trailing,
                    isEnabled: relatedCharts?.isEmpty == false && dragMode == .none
                ) { onHoverChanged, onDialogActiveChanged in
                    MeasurementPlotPreviewPanel(
                        references: relatedCharts ?? [],
                        libraryRootURL: libraryRootURL,
                        onHoverChanged: onHoverChanged,
                        onDialogActiveChanged: onDialogActiveChanged
                    )
                }
        } else {
            ContentUnavailableView(
                "No Plot",
                systemImage: "chart.xyaxis.line",
                description: Text("Select measurements and press Plot.")
            )
            .frame(maxWidth: .infinity, minHeight: minHeight)
        }
    }

    // MARK: - Legend drag preview

    @ViewBuilder
    private var legendDragPreview: some View {
        if let pt = dragPreviewPt {
            let fitted = fittedRect(in: canvasSize)
            if fitted.width > 0 && fitted.height > 0 {
                // Legend geometry is authored in layout's logical CG space, not image pixels.
                let rSize = layout?.rendererSize ?? rendererPixelSize
                let scaleX  = fitted.width  / rSize.width
                let scaleY  = fitted.height / rSize.height
                let boxPad: CGFloat = 6
                let rowCount = CGFloat(layout?.legendRows.count ?? 1)
                // Use the CoreText-measured max label width so the preview box matches the
                // rendered legend box exactly (same formula as drawLegend).
                let maxLabelW = layout?.legendRows.map(\.measuredLabelWidth).max()
                              ?? WorkbenchPlotLayout.legendEstLabelW
                let boxW = (WorkbenchPlotLayout.legendLineLen
                          + WorkbenchPlotLayout.legendGap
                          + maxLabelW
                          + 2 * boxPad) * scaleX
                let boxH = (rowCount * WorkbenchPlotLayout.legendRowH + 2 * boxPad) * scaleY
                // pt is screen position of (cgOriginX, originY).
                // Legend box top-left is offset by (-boxPad, -(0.1*rowH + boxPad)) in renderer space.
                let topLeftX = pt.x - boxPad * scaleX
                let topLeftY = pt.y - (WorkbenchPlotLayout.legendRowH * 0.1 + boxPad) * scaleY
                Rectangle()
                    .strokeBorder(
                        Color.accentColor.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                    )
                    .frame(width: boxW, height: boxH)
                    .position(x: topLeftX + boxW / 2, y: topLeftY + boxH / 2)
            }
        }
    }

    // MARK: - Series drag guide

    @ViewBuilder
    private var seriesDragGuidePreview: some View {
        if case .series = dragMode, let yScreen = seriesGuideYScreen, let l = layout {
            let fitted = fittedRect(in: canvasSize)
            if fitted.width > 0 {
                let scaleX = fitted.width / l.rendererSize.width
                let plotMinX = fitted.minX + l.plotRect.minX * scaleX
                let plotMaxX = fitted.minX + l.plotRect.maxX * scaleX
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
    }

    private func _isInLegendArea(_ location: CGPoint, fittedRect: CGRect) -> Bool {
        guard let l = layout else { return false }
        for row in l.legendRows {
            let screenRect = WorkbenchPlotLayout.cgToScreen(
                row.hitRect, fittedIn: fittedRect,
                rendererWidth: l.rendererSize.width, rendererHeight: l.rendererSize.height
            )
            if screenRect.contains(location) { return true }
        }
        return false
    }

    private func _computeNewSeriesOrder(
        draggedSampleID: String,
        guideYScreen: CGFloat,
        payload: WorkbenchPlotPayload,
        layout: WorkbenchPlotLayout,
        fittedRect: CGRect
    ) -> [String] {
        let series = payload.series
        let allX = series.flatMap(\.x)
        let allY = series.flatMap(\.y)
        guard !allX.isEmpty else { return series.compactMap(\.sampleID) }

        let xRaw = allX.min()!, xRawMax = allX.max()!
        let yRaw = allY.min()!, yRawMax = allY.max()!
        let yRawSpan = yRawMax == yRaw ? 1.0 : yRawMax - yRaw
        let yMin = yRaw - yRawSpan * 0.05
        let yMax = yRawMax + yRawSpan * 0.05
        let ySpan = yMax - yMin
        guard ySpan > 0 else { return series.compactMap(\.sampleID) }
        _ = xRaw; _ = xRawMax   // suppress unused warnings

        let scaleY = fittedRect.height / layout.rendererSize.height

        func cgToScreenY(_ y: Double) -> CGFloat {
            let cgY = layout.plotRect.minY + CGFloat((y - yMin) / ySpan) * layout.plotRect.height
            return fittedRect.minY + (layout.rendererSize.height - cgY) * scaleY
        }

        var pairs: [(id: String, screenY: CGFloat)] = []
        for s in series {
            guard let id = s.sampleID, !s.y.isEmpty else { continue }
            let y: CGFloat = id == draggedSampleID
                ? guideYScreen
                : cgToScreenY(s.y[s.y.count / 2])
            pairs.append((id, y))
        }

        // Screen y ascending = top → bottom; seriesOrder is bottom → top, so reverse.
        return pairs.sorted { $0.screenY < $1.screenY }.reversed().map(\.id)
    }

    /// Returns the current legend origin as a normalized plot point (x,y ∈ [0,1], Y-up).
    /// Derived from legendRows[0] by reversing the renderer's free-position math.
    /// Falls back to (0.5, 0.5) when layout is unavailable.
    private func currentLegendOriginNorm() -> CGPoint {
        guard let layout, !layout.legendRows.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let pr = layout.plotRect
        let row0 = layout.legendRows[0]
        let nx = (row0.cgOriginX - pr.minX) / pr.width
        // Reverse: originY = cgRowY + legendRowH * 0.4  (from computeLegendRows, i=0)
        let cgOriginY = row0.cgRowY + WorkbenchPlotLayout.legendRowH * 0.4
        let ny = (cgOriginY - pr.minY) / pr.height
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    // MARK: - Inline edit panel

    // Estimated panel dimensions for positioning (actual may vary slightly).
    private static let panelW: CGFloat = 340
    private static let panelH: CGFloat = 38

    @ViewBuilder
    private func editPanel(for elem: EditTarget) -> some View {
        let label: String = {
            switch elem {
            case .title:            return "Title"
            case .xLabel:           return "X Label"
            case .yLabel:           return "Y Label"
            case .legend(_, let orig):  return "Legend · \(orig)"
            case .xTickLabel:       return "X Tick"
            case .yTickLabel:       return "Y Tick"
            case .pointLabel:       return "Point Label"
            case .pointDot:         return ""
            }
        }()
        let hasTextField: Bool = {
            switch elem {
            case .xTickLabel, .yTickLabel, .pointLabel, .pointDot: return false
            default: return true
            }
        }()
        let pos = editPanelPosition()
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if hasTextField {
                TextField("", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100, maxWidth: 180)
                    .onSubmit { commitEdit() }
            }
            if let key = editFontSizeKey, onFontSizeChange != nil {
                fontSizePicker(key: key)
            }
            if let densityKey = editTickDensityKey {
                tickDensityStepper(key: densityKey)
            }
            if hasTextField {
                Button("OK")     { commitEdit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                if case .title = elem {
                    Button("Default") {
                        editText = ""
                        commitEdit()
                    }
                    .controlSize(.small)
                }
            } else {
                Button("OK") { editingElement = nil }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button("Cancel") { editingElement = nil }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: Self.panelW)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .position(pos)
        .onExitCommand { editingElement = nil }
    }

    @ViewBuilder
    private func fontSizePicker(key: String) -> some View {
        let defaultSize: CGFloat = WorkbenchChartStyle()[keyPath: Self.fontSizeKeyPath(key)]
        let current = chartStyleOverrides[key].flatMap { Double($0).map { CGFloat($0) } } ?? defaultSize
        Picker("", selection: Binding<CGFloat>(
            get: { current },
            set: { newVal in
                onFontSizeChange?(key, newVal)
            }
        )) {
            ForEach(Self.fontSizeOptions, id: \.self) { s in
                Text("\(Int(s))pt").tag(s)
            }
        }
        .labelsHidden()
        .frame(width: 72)
    }

    @ViewBuilder
    private func tickDensityStepper(key: String) -> some View {
        let fallback = key == "tickTargetX" ? 6 : 5
        let current = chartStyleOverrides[key].flatMap { Int($0) } ?? fallback
        HStack(spacing: 4) {
            Text("Density").font(.caption2).foregroundStyle(.secondary).fixedSize()
            Stepper(
                value: Binding<Int>(
                    get: { current },
                    set: { newVal in
                        onStyleOverrideChange?(key, "\(newVal)")
                    }
                ),
                in: 2...20
            ) {
                Text("\(current)").font(.caption).frame(width: 20)
            }
            .frame(width: 90)
        }
    }

    private static func fontSizeKeyPath(_ key: String) -> KeyPath<WorkbenchChartStyle, CGFloat> {
        switch key {
        case "titleFontSize":     return \.titleFontSize
        case "axisTitleFontSize": return \.axisTitleFontSize
        case "tickLabelFontSize": return \.tickLabelFontSize
        case "legendFontSize":        return \.legendFontSize
        case "pointLabelFontSize":    return \.pointLabelFontSize
        default:                      return \.titleFontSize
        }
    }

    /// Returns the `.position` (center point) for the edit panel, keeping it within the canvas.
    private func editPanelPosition() -> CGPoint {
        let halfW = Self.panelW / 2
        let halfH = Self.panelH / 2
        let gap: CGFloat = 6
        let r = editTargetScreenRect

        // Prefer above the element; fall back to below when there's not enough room.
        let yAbove = r.minY - gap - halfH
        let yBelow = r.maxY + gap + halfH
        let preferY = yAbove >= halfH + 4 ? yAbove : yBelow

        let clampedX = min(max(r.midX, halfW + 8), canvasSize.width  - halfW - 8)
        let clampedY = min(max(preferY, halfH + 4), canvasSize.height - halfH - 4)
        return CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Tap hit-testing

    private func handleTap(at location: CGPoint) {
        guard let layout else { return }
        let fitted = fittedRect(in: canvasSize)
        // Hit rects are produced in layout's logical CG space (options.width × options.height).
        // The on-screen image is rendered at pixelScale (default 2x), so its pixel size differs.
        // Use layout.rendererSize for the screen mapping; rendererPixelSize is image-pixel space.
        let rW = layout.rendererSize.width
        let rH = layout.rendererSize.height

        func toScreen(_ cr: CGRect) -> CGRect {
            WorkbenchPlotLayout.cgToScreen(cr, fittedIn: fitted,
                                           rendererWidth: rW, rendererHeight: rH)
        }

        if onEditTitle != nil, toScreen(layout.titleHitRect).contains(location) {
            editText = layout.chartTitle
            editTargetScreenRect = toScreen(layout.titleHitRect)
            editingElement = .title
            return
        }
        if onEditXLabel != nil, toScreen(layout.xLabelHitRect).contains(location) {
            editText = layout.xAxisLabel
            editTargetScreenRect = toScreen(layout.xLabelHitRect)
            editingElement = .xLabel
            return
        }
        if onEditYLabel != nil, toScreen(layout.yLabelHitRect).contains(location) {
            editText = layout.yAxisLabel
            editTargetScreenRect = toScreen(layout.yLabelHitRect)
            editingElement = .yLabel
            return
        }
        if onEditLegendLabel != nil {
            for row in layout.legendRows {
                let sr = toScreen(row.hitRect)
                if sr.contains(location) {
                    let key: String
                    if let sid = seriesPayload?.series[safe: row.seriesIndex]?.sampleID {
                        key = sid
                    } else {
                        key = String(row.seriesIndex)
                    }
                    editText = seriesLabelOverrides[key] ?? row.originalLabel
                    editTargetScreenRect = sr
                    editingElement = .legend(key: key, originalLabel: row.originalLabel)
                    return
                }
            }
        }
        // Point dot hit-test -> toggle visibility (higher priority than tick-label regions)
        if onTogglePointLabelVisibility != nil, !layout.pointDotHitTargets.isEmpty {
            for target in layout.pointDotHitTargets {
                if toScreen(target.hitRect).contains(location) {
                    let key: String
                    if let sid = seriesPayload?.series[safe: target.seriesIndex]?.sampleID {
                        key = sid
                    } else {
                        key = String(target.seriesIndex)
                    }
                    onTogglePointLabelVisibility?(key, target.pointIndex)
                    return
                }
            }
        }
        // Point label hit-test -> open point-label font-size editor
        if onFontSizeChange != nil, !layout.pointLabelHitTargets.isEmpty {
            for target in layout.pointLabelHitTargets {
                if toScreen(target.hitRect).contains(location) {
                    editTargetScreenRect = toScreen(target.hitRect)
                    editingElement = .pointLabel(seriesIndex: target.seriesIndex, pointIndex: target.pointIndex)
                    return
                }
            }
        }
        if onFontSizeChange != nil {
            if toScreen(layout.xTickHitRect).contains(location) {
                editTargetScreenRect = toScreen(layout.xTickHitRect)
                editingElement = .xTickLabel
                return
            }
            if toScreen(layout.yTickHitRect).contains(location) {
                editTargetScreenRect = toScreen(layout.yTickHitRect)
                editingElement = .yTickLabel
                return
            }
        }
        // Tap outside any editable element — dismiss active editor
        if editingElement != nil { editingElement = nil }
    }

    private func commitEdit() {
        guard let elem = editingElement else { return }
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elem {
        case .title:              onEditTitle?(text)
        case .xLabel:             onEditXLabel?(text)
        case .yLabel:             onEditYLabel?(text)
        case .legend(let key, _): onEditLegendLabel?(key, text)
        case .xTickLabel, .yTickLabel, .pointLabel, .pointDot: break
        }
        editingElement = nil
        editText = ""
    }

    // MARK: - Geometry helpers

    private func fittedRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let imageAspect = rendererPixelSize.width / rendererPixelSize.height
        let containerAspect = size.width / size.height
        let w: CGFloat
        let h: CGFloat
        if containerAspect > imageAspect {
            h = size.height; w = h * imageAspect
        } else {
            w = size.width; h = w / imageAspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func plotNormalized(location: CGPoint, fittedRect: CGRect) -> CGPoint? {
        guard !fittedRect.isEmpty else { return nil }
        let rSize = layout?.rendererSize ?? rendererPixelSize
        let pr = layout?.plotRect ?? {
            let opts = WorkbenchChartRenderer.Options()
            return CGRect(
                x: opts.paddingLeft, y: opts.paddingBottom,
                width: rSize.width - opts.paddingLeft - opts.paddingRight,
                height: rSize.height - opts.paddingTop - opts.paddingBottom
            )
        }()
        // Clamp cursor to fittedRect before projecting so dragging outside the image
        // (or into any padding margin) stays responsive with no invisible air wall.
        let cx = min(max(location.x, fittedRect.minX), fittedRect.maxX)
        let cy = min(max(location.y, fittedRect.minY), fittedRect.maxY)
        let px = (cx - fittedRect.minX) / fittedRect.width  * rSize.width
        let py = (cy - fittedRect.minY) / fittedRect.height * rSize.height
        // CG layout: plotRect origin is bottom-left, but in PNG space Y is inverted.
        // pr.minX = paddingLeft, pr.minY = paddingBottom (CG), but in PNG space
        // the top of the plot is at paddingTop from the top of the image.
        let plotMinX = pr.minX
        let plotMinY = rSize.height - pr.maxY   // PNG-space top of plot area
        let nx = (px - plotMinX) / pr.width
        let ny = 1.0 - (py - plotMinY) / pr.height
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    /// Converts a normalized legend point (0-1, Y-up) back to the screen-space top-left of the
    /// legend block — the same position the renderer will place cgOriginX / originY.
    /// This is the inverse of `plotNormalized`, ensuring the preview anchors exactly to the
    /// rendered legend origin rather than the raw drag location.
    private func legendScreenOrigin(normalized: CGPoint, fittedRect: CGRect) -> CGPoint {
        let rSize = layout?.rendererSize ?? rendererPixelSize
        let pr = layout?.plotRect ?? {
            let opts = WorkbenchChartRenderer.Options()
            return CGRect(
                x: opts.paddingLeft, y: opts.paddingBottom,
                width: rSize.width - opts.paddingLeft - opts.paddingRight,
                height: rSize.height - opts.paddingTop - opts.paddingBottom
            )
        }()
        // Renderer CG space (Y-up)
        let cgOriginX = pr.minX + normalized.x * pr.width
        let cgOriginY = pr.minY + normalized.y * pr.height
        // PNG space (Y-down, same as screen)
        let pngX = cgOriginX
        let pngY = rSize.height - cgOriginY
        return CGPoint(
            x: fittedRect.minX + pngX / rSize.width  * fittedRect.width,
            y: fittedRect.minY + pngY / rSize.height * fittedRect.height
        )
    }

    private static func extractRendererPixelSize(from image: NSImage) -> CGSize? {
        for rep in image.representations {
            let size = CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
            if size.width > 0, size.height > 0 { return size }
        }
        return nil
    }
}
