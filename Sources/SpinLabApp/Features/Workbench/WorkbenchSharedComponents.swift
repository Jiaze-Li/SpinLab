import SwiftUI
import AppKit

// MARK: - WorkbenchPlottingStore

/// 所有 workflow workspace store 必须实现的 canvas 交互合约。
/// 确保任何新 workflow 都能接入 WorkbenchPlotCanvas 的拖拽、行内编辑等交互。
@MainActor
protocol WorkbenchPlottingStore: AnyObject {
    /// 是否显示网格线。
    var showPlotGrid: Bool { get set }
    /// 最近一次运行的 trace（nil = 尚未运行）。
    var currentRunTrace: WorkbenchRunTraceProjection? { get }
    /// 用户拖拽图例后回调，point 为 plot 归一化坐标（x,y ∈ [0,1]，Y-up）。
    func updateLegendPoint(_ point: CGPoint)
    /// 用户行内编辑图表标题后回调。
    func updatePlotTitle(_ title: String)
    /// 用户行内编辑 X 轴标签后回调。
    func updateXAxisLabel(_ label: String)
    /// 用户行内编辑 Y 轴标签后回调。
    func updateYAxisLabel(_ label: String)
    /// 用户重命名图例标签后回调。
    func updateSeriesLabel(index: Int, newLabel: String)
}

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
    /// Current series label overrides keyed by series index, used to pre-fill the edit field.
    var seriesLabelOverrides: [Int: String] = [:]

    /// Called with a plotRect-normalized point (x,y ∈ [0,1], y=0 bottom, y=1 top)
    /// when the user finishes a drag over the plot area. Nil = drag disabled.
    var onLegendDrag: ((CGPoint) -> Void)? = nil
    /// Inline edit callbacks — nil means that element is not editable.
    var onEditTitle:       ((String) -> Void)?               = nil
    var onEditXLabel:      ((String) -> Void)?               = nil
    var onEditYLabel:      ((String) -> Void)?               = nil
    /// (seriesIndex, newLabel)
    var onEditLegendLabel: ((Int, String) -> Void)?          = nil

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
    /// Which chart element is currently being edited.
    @State private var editingElement: EditTarget? = nil
    /// Live text for the active edit field.
    @State private var editText: String = ""
    /// Screen-space rect of the element being edited, used to position the edit panel.
    @State private var editTargetScreenRect: CGRect = .zero
    /// Pixel size of the current rendered PNG used for coordinate conversion.
    /// Falls back to 800x600 until image metadata is available.
    @State private var rendererPixelSize: CGSize = CGSize(width: 800, height: 600)

    private static let defaultRendererSize = CGSize(width: 800, height: 600)

    private enum EditTarget: Equatable {
        case title
        case xLabel
        case yLabel
        case legend(seriesIndex: Int, originalLabel: String)
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
                .overlay {
                    if let elem = editingElement {
                        editPanel(for: elem)
                    }
                }
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleTap(at: value.location)
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard onLegendDrag != nil else { return }
                            let fitted = fittedRect(in: canvasSize)
                            // plotNormalized always returns a value (clamps to fitted+plot boundary).
                            guard let cursorNorm = plotNormalized(location: value.location, fittedRect: fitted) else { return }
                            // Capture grab offset once using startLocation (not first-frame location)
                            // to avoid the minimumDistance:4 threshold causing a positional jump.
                            if dragGrabOffsetNorm == nil {
                                let startNorm = plotNormalized(location: value.startLocation, fittedRect: fitted) ?? cursorNorm
                                let origin = currentLegendOriginNorm()
                                dragGrabOffsetNorm = CGSize(
                                    width:  startNorm.x - origin.x,
                                    height: startNorm.y - origin.y
                                )
                            }
                            let grab = dragGrabOffsetNorm ?? .zero
                            // Legend origin follows cursor minus the grab offset.
                            // cursorNorm is already clamped to [0,1] so adjusted is too.
                            let adjusted = CGPoint(
                                x: min(max(cursorNorm.x - grab.width,  0), 1),
                                y: min(max(cursorNorm.y - grab.height, 0), 1)
                            )
                            lastValidDragNorm = adjusted
                            dragPreviewPt = legendScreenOrigin(normalized: adjusted, fittedRect: fitted)
                        }
                        .onEnded { value in
                            let last = lastValidDragNorm
                            dragPreviewPt      = nil
                            dragGrabOffsetNorm = nil
                            lastValidDragNorm  = nil
                            guard let callback = onLegendDrag, let finalNorm = last else { return }
                            // finalNorm is already clamped to [0,1] from onChanged.
                            // It matches exactly the last preview position, so landing = preview.
                            callback(finalNorm)
                        }
                )
                .onAppear {
                    rendererPixelSize = Self.extractRendererPixelSize(from: nsImage) ?? Self.defaultRendererSize
                }
                .onChange(of: imageData) { _, _ in
                    rendererPixelSize = Self.extractRendererPixelSize(from: nsImage) ?? Self.defaultRendererSize
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
                let scaleX  = fitted.width  / rendererPixelSize.width
                let scaleY  = fitted.height / rendererPixelSize.height
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

    /// Returns the current legend origin as a normalized plot point (x,y ∈ [0,1], Y-up).
    /// Derived from legendRows[0] by reversing the renderer's free-position math.
    /// Falls back to (0.5, 0.5) when layout is unavailable.
    private func currentLegendOriginNorm() -> CGPoint {
        guard let rows = layout?.legendRows, !rows.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let opts = WorkbenchChartRenderer.Options()
        let plotMinX = opts.paddingLeft
        let plotMinY = opts.paddingBottom   // CG Y-up: plot bottom edge
        let plotW = rendererPixelSize.width  - opts.paddingLeft - opts.paddingRight
        let plotH = rendererPixelSize.height - opts.paddingTop  - opts.paddingBottom
        let row0 = rows[0]
        let nx = (row0.cgOriginX - plotMinX) / plotW
        // Reverse: originY = cgRowY + legendRowH * 0.4  (from computeLegendRows, i=0)
        let cgOriginY = row0.cgRowY + WorkbenchPlotLayout.legendRowH * 0.4
        let ny = (cgOriginY - plotMinY) / plotH
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
            case .legend(_, let orig): return "Legend · \(orig)"
            }
        }()
        let pos = editPanelPosition()
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            TextField("", text: $editText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 220)
                .onSubmit { commitEdit() }
            Button("OK")     { commitEdit() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Cancel") { editingElement = nil }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: Self.panelW)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .position(pos)
        .onExitCommand { editingElement = nil }
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
        let rW = rendererPixelSize.width
        let rH = rendererPixelSize.height

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
                    editText = seriesLabelOverrides[row.seriesIndex] ?? row.originalLabel
                    editTargetScreenRect = sr
                    editingElement = .legend(seriesIndex: row.seriesIndex, originalLabel: row.originalLabel)
                    return
                }
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
        case .legend(let idx, _): onEditLegendLabel?(idx, text)
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
        // Clamp cursor to fittedRect before projecting so dragging outside the image
        // (or into any padding margin) stays responsive with no invisible air wall.
        let cx = min(max(location.x, fittedRect.minX), fittedRect.maxX)
        let cy = min(max(location.y, fittedRect.minY), fittedRect.maxY)
        let px = (cx - fittedRect.minX) / fittedRect.width  * rendererPixelSize.width
        let py = (cy - fittedRect.minY) / fittedRect.height * rendererPixelSize.height
        let opts = WorkbenchChartRenderer.Options()
        let plotW    = rendererPixelSize.width  - opts.paddingLeft - opts.paddingRight
        let plotH    = rendererPixelSize.height - opts.paddingTop  - opts.paddingBottom
        let plotMinX = opts.paddingLeft
        let plotMinY = opts.paddingTop
        let nx = (px - plotMinX) / plotW
        let ny = 1.0 - (py - plotMinY) / plotH
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    /// Converts a normalized legend point (0-1, Y-up) back to the screen-space top-left of the
    /// legend block — the same position the renderer will place cgOriginX / originY.
    /// This is the inverse of `plotNormalized`, ensuring the preview anchors exactly to the
    /// rendered legend origin rather than the raw drag location.
    private func legendScreenOrigin(normalized: CGPoint, fittedRect: CGRect) -> CGPoint {
        let opts = WorkbenchChartRenderer.Options()
        let plotW = rendererPixelSize.width  - opts.paddingLeft - opts.paddingRight
        let plotH = rendererPixelSize.height - opts.paddingTop  - opts.paddingBottom
        // Renderer CG space (Y-up)
        let cgOriginX = opts.paddingLeft   + normalized.x * plotW
        let cgOriginY = opts.paddingBottom + normalized.y * plotH
        // PNG space (Y-down, same as screen)
        let pngX = cgOriginX
        let pngY = rendererPixelSize.height - cgOriginY
        return CGPoint(
            x: fittedRect.minX + pngX / rendererPixelSize.width  * fittedRect.width,
            y: fittedRect.minY + pngY / rendererPixelSize.height * fittedRect.height
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

// MARK: - WorkbenchTracePanel

/// 通用 run trace 面板。
/// trace 为 nil 时自动隐藏。
///
/// ## 自定义提示
/// - `traceRow` 的 label 宽度（`labelWidth`）可调
/// - GroupBox 标题可按需修改
struct WorkbenchTracePanel: View {
    let trace: WorkbenchRunTraceProjection?

    // TODO(用户设计): 调整 label 列宽、字号、是否折叠显示
    var labelWidth: CGFloat = 64

    var body: some View {
        if let trace {
            GroupBox("Last Run Trace") {
                VStack(alignment: .leading, spacing: 6) {
                    traceRow(label: "Run ID",    value: trace.runID)
                    traceRow(label: "Workflow",  value: trace.workflowID)
                    traceRow(label: "X Axis",    value: trace.axisMapping.xField)
                    traceRow(label: "Y Axis",    value: trace.axisMapping.yField)
                    traceRow(label: "Inputs",    value: trace.inputFiles.joined(separator: "\n"))
                    traceRow(label: "Output",    value: trace.outputImagePath)
                    traceRow(label: "Generated", value: trace.generatedAt.formatted(.dateTime))
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func traceRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - WorkbenchStatusArea

/// 通用状态消息区。
/// 三条消息各自独立，非空才显示，全空时整个 view 不占空间。
///
/// ## 自定义提示
/// - 字号、颜色、消息合并方式可按需修改
struct WorkbenchStatusArea: View {
    let searchMessage: String?
    let plotMessage: String?
    let loadMessage: String?

    // TODO(用户设计): 考虑是否合并为单条消息、是否加图标前缀
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let msg = searchMessage, !msg.isEmpty {
                Text(msg).font(.footnote).foregroundStyle(.secondary)
            }
            if let msg = plotMessage, !msg.isEmpty {
                Text(msg).font(.footnote).foregroundStyle(.secondary)
            }
            if let msg = loadMessage, !msg.isEmpty {
                Text(msg).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - WorkbenchPlotControlsPanel

/// 通用 Plot Controls 容器。
/// 提供统一的 GroupBox 标题、内部 VStack 间距和 padding。
/// 所有 workflow 的 PlotControlsPanel 必须以此为容器，workflow 专属控件通过 ViewBuilder 注入。
struct WorkbenchPlotControlsPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - WorkbenchTitleTemplateField

/// Shared title template input field with dynamic hint showing available tokens.
/// Used by 3ω and AHE plot controls.
struct WorkbenchTitleTemplateField: View {
    @Binding var titleTemplate: String
    let numericDisplayCache: [String: [String: String]]
    var onChange: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Title")
                    .font(.body)
                TextField("#tab #device #sample", text: $titleTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onChange(of: titleTemplate) { _, _ in
                        onChange?()
                    }
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var hint: String {
        var tokens = ["#tab", "#method", "#device", "#sample"]
        let numericKeys = numericDisplayCache.values.flatMap { $0.keys }
        for key in Set(numericKeys).sorted() {
            tokens.append("#\(key)")
        }
        return "Available: " + tokens.joined(separator: " ")
    }
}

// MARK: - WorkflowHitRow

/// 通用搜索结果行。
/// 适用于所有 workflow 的 WorkflowMeasurementSearchHit 显示。
struct WorkflowHitRow: View {
    let hit: WorkflowMeasurementSearchHit
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Workflow").font(.caption).foregroundStyle(.secondary)
                    Text(hit.workflowDisplayName).font(.body.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Sample").font(.caption).foregroundStyle(.secondary)
                    Text(hit.sampleBatchAndSubstrate)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Condition").font(.caption).foregroundStyle(.secondary)
                    Text(hit.conditionSummary).font(.callout)
                }
                if !hit.channels.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Channels").font(.caption).foregroundStyle(.secondary)
                        Text(hit.channels.joined(separator: ", ")).font(.callout)
                    }
                }
                Text(hit.measurementFilePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .onTapGesture(perform: onTap)
    }
}
