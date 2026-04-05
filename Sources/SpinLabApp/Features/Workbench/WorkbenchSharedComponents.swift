import SwiftUI
import AppKit

// MARK: - WorkbenchPlotCanvas

/// 通用图像显示组件。
/// 有数据时显示渲染好的 PNG，无数据时显示占位符。
///
/// ## 自定义提示
/// - `minHeight` 控制最小显示高度
/// - 占位符图标和文字可按需修改
struct WorkbenchPlotCanvas: View {
    let imageData: Data?
    /// Called with a plotRect-normalized point (x,y ∈ [0,1], y=0 bottom, y=1 top)
    /// when the user finishes a drag over the plot area. Nil = drag disabled.
    var onLegendDrag: ((CGPoint) -> Void)? = nil

    // TODO(用户设计): 调整最小高度、背景样式、空状态文字
    var minHeight: CGFloat = 360

    @State private var canvasSize: CGSize = .zero
    /// Screen-space point of an in-progress drag (nil when not dragging).
    @State private var dragPreviewPt: CGPoint? = nil

    private static let rendererSize = CGSize(width: 800, height: 600)

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
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard onLegendDrag != nil else { return }
                            let fitted = fittedRect(in: canvasSize)
                            // Show preview only when drag is within the plot area
                            if plotNormalized(location: value.location, fittedRect: fitted) != nil {
                                dragPreviewPt = value.location
                            } else {
                                dragPreviewPt = nil
                            }
                        }
                        .onEnded { value in
                            dragPreviewPt = nil
                            guard let callback = onLegendDrag else { return }
                            let fitted = fittedRect(in: canvasSize)
                            guard let pt = plotNormalized(location: value.location,
                                                          fittedRect: fitted) else { return }
                            callback(pt)
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

    /// Dashed rectangle preview shown while dragging. Top-left anchored at drag location.
    @ViewBuilder
    private var legendDragPreview: some View {
        if let pt = dragPreviewPt {
            let boxW: CGFloat = 96
            let boxH: CGFloat = 28
            Rectangle()
                .strokeBorder(
                    Color.accentColor.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                )
                .frame(width: boxW, height: boxH)
                // .position centers the view; offset so pt is the top-left corner
                .position(x: pt.x + boxW / 2, y: pt.y + boxH / 2)
        }
    }

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
                    traceRow(label: "Identity",  value: trace.chartIdentityKey)
                    traceRow(label: "Generated", value: trace.generatedAt.formatted(.dateTime))
                    traceRow(label: "Version",   value: trace.appVersion)
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
