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

    private static let rendererSize = CGSize(width: 800, height: 600)

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
                            guard let cursorNorm = plotNormalized(location: value.location, fittedRect: fitted) else {
                                // Cursor left plot area — keep last preview position.
                                return
                            }
                            // Capture grab offset once on the first valid drag frame.
                            if dragGrabOffsetNorm == nil {
                                let origin = currentLegendOriginNorm()
                                dragGrabOffsetNorm = CGSize(
                                    width:  cursorNorm.x - origin.x,
                                    height: cursorNorm.y - origin.y
                                )
                            }
                            let grab = dragGrabOffsetNorm ?? .zero
                            let adjusted = CGPoint(
                                x: cursorNorm.x - grab.width,
                                y: cursorNorm.y - grab.height
                            )
                            lastValidDragNorm = adjusted
                            // Clamp only for preview so it matches the renderer's clamped output.
                            // The unclamped value is kept in lastValidDragNorm / callback so the
                            // cursor can reach the actual plot boundary without an air wall.
                            let previewNorm = CGPoint(
                                x: min(max(adjusted.x, 0), 1),
                                y: min(max(adjusted.y, 0), 1)
                            )
                            dragPreviewPt = legendScreenOrigin(normalized: previewNorm, fittedRect: fitted)
                        }
                        .onEnded { value in
                            let grab      = dragGrabOffsetNorm ?? .zero
                            let lastNorm  = lastValidDragNorm
                            dragPreviewPt     = nil
                            dragGrabOffsetNorm = nil
                            lastValidDragNorm  = nil
                            guard let callback = onLegendDrag else { return }
                            let fitted = fittedRect(in: canvasSize)
                            // Prefer cursor position; fall back to last valid position from onChanged
                            // (handles the case where the cursor lands in the padding area on release).
                            let finalNorm: CGPoint
                            if let cn = plotNormalized(location: value.location, fittedRect: fitted) {
                                finalNorm = CGPoint(
                                    x: cn.x - grab.width,
                                    y: cn.y - grab.height
                                )
                            } else if let last = lastNorm {
                                finalNorm = last
                            } else {
                                return
                            }
                            callback(finalNorm)
                        }
                )
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
                let opts    = WorkbenchChartRenderer.Options()
                let scaleX  = fitted.width  / CGFloat(opts.width)
                let scaleY  = fitted.height / CGFloat(opts.height)
                let boxPad: CGFloat = 6
                let rowCount = CGFloat(layout?.legendRows.count ?? 1)
                // Match drawLegend's exact box formula, scaled to screen space.
                let boxW = (WorkbenchPlotLayout.legendLineLen
                          + WorkbenchPlotLayout.legendGap
                          + WorkbenchPlotLayout.legendEstLabelW
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
        let plotW = CGFloat(opts.width)  - opts.paddingLeft - opts.paddingRight
        let plotH = CGFloat(opts.height) - opts.paddingTop  - opts.paddingBottom
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
        let rW = Self.rendererSize.width
        let rH = Self.rendererSize.height

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
        let imageAspect = Self.rendererSize.width / Self.rendererSize.height
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
        guard !fittedRect.isEmpty, fittedRect.contains(location) else { return nil }
        let px = (location.x - fittedRect.minX) / fittedRect.width  * Self.rendererSize.width
        let py = (location.y - fittedRect.minY) / fittedRect.height * Self.rendererSize.height
        let opts = WorkbenchChartRenderer.Options()
        let plotW    = CGFloat(opts.width)  - opts.paddingLeft - opts.paddingRight
        let plotH    = CGFloat(opts.height) - opts.paddingTop  - opts.paddingBottom
        let plotMinX = opts.paddingLeft
        let plotMinY = opts.paddingTop
        guard px >= plotMinX, px <= plotMinX + plotW,
              py >= plotMinY, py <= plotMinY + plotH else { return nil }
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
        let plotW = CGFloat(opts.width)  - opts.paddingLeft - opts.paddingRight
        let plotH = CGFloat(opts.height) - opts.paddingTop  - opts.paddingBottom
        // Renderer CG space (Y-up)
        let cgOriginX = opts.paddingLeft   + normalized.x * plotW
        let cgOriginY = opts.paddingBottom + normalized.y * plotH
        // PNG space (Y-down, same as screen)
        let pngX = cgOriginX
        let pngY = CGFloat(opts.height) - cgOriginY
        return CGPoint(
            x: fittedRect.minX + pngX / CGFloat(opts.width)  * fittedRect.width,
            y: fittedRect.minY + pngY / CGFloat(opts.height) * fittedRect.height
        )
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
