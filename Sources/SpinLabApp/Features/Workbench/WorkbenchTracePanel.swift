import SwiftUI

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
        GroupBox("Last Run Trace") {
            if let trace {
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
            } else {
                Text("No trace yet — run analysis to generate.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
