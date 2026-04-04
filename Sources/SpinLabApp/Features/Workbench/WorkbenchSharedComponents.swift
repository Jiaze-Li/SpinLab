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

    // TODO(用户设计): 调整最小高度、背景样式、空状态文字
    var minHeight: CGFloat = 360

    var body: some View {
        if let data = imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
