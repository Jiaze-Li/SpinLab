import SwiftUI

// MARK: - WorkbenchPlotControlsPanel

/// 通用 Plot Controls 容器。
/// 提供统一的 GroupBox 标题、内部 VStack 间距和 padding。
/// 所有 workflow 的 PlotControlsPanel 必须以此为容器，workflow 专属控件通过 ViewBuilder 注入。
/// Shell 级控件（绘图模式、tick 密度）自动附加在底部。
/// 字号通过点击图上元素调整，不在此面板。
struct WorkbenchPlotControlsPanel<Content: View, Supplemental: View>: View {
    @Binding var seriesRenderMode: SeriesRenderMode
    @Binding var chartStyleOverrides: [String: String]
    var onStyleChange: (() -> Void)? = nil
    @ViewBuilder var supplementalContent: () -> Supplemental
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                content()
                // Shell-level control: render mode
                HStack(spacing: 8) {
                    Text("Draw").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $seriesRenderMode) {
                        Text("Line").tag(SeriesRenderMode.line)
                        Text("Scatter").tag(SeriesRenderMode.scatter)
                        Text("Line+Scatter").tag(SeriesRenderMode.lineAndScatter)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: seriesRenderMode) { _, _ in onStyleChange?() }
                }
                supplementalContent()
            }
            .padding(.vertical, 4)
        }
    }

}

extension WorkbenchPlotControlsPanel where Supplemental == EmptyView {
    init(
        seriesRenderMode: Binding<SeriesRenderMode>,
        chartStyleOverrides: Binding<[String: String]>,
        onStyleChange: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._seriesRenderMode = seriesRenderMode
        self._chartStyleOverrides = chartStyleOverrides
        self.onStyleChange = onStyleChange
        self.supplementalContent = { EmptyView() }
        self.content = content
    }
}
