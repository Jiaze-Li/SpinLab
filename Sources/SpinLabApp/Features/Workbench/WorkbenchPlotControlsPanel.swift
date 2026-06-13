import SwiftUI

private let _plotControlsFontSizeOptions: [CGFloat] = [12, 14, 16, 18, 19, 20, 22, 24, 25, 28, 32]

// MARK: - WorkbenchPlotControlsPanel

/// 通用 Plot Controls 容器。
/// 提供统一的 GroupBox 标题、内部 VStack 间距和 padding。
/// 所有 workflow 的 PlotControlsPanel 必须以此为容器，workflow 专属控件通过 ViewBuilder 注入。
/// Shell 级控件（绘图模式、字号、tick 密度）自动附加在底部。
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
                // Shell-level: render mode + tick density in one row
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
                    Spacer(minLength: 8)
                    Text("Ticks").font(.caption).foregroundStyle(.secondary).fixedSize()
                    tickDensityStepper(label: "X", key: "tickTargetX", fallback: 6)
                    tickDensityStepper(label: "Y", key: "tickTargetY", fallback: 5)
                }
                // Shell-level controls: font sizes
                fontSizeRow
                supplementalContent()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var fontSizeRow: some View {
        HStack(spacing: 10) {
            Text("Size").font(.caption).foregroundStyle(.secondary).fixedSize()
            ForEach([
                ("Title", "titleFontSize"),
                ("Axis",  "axisTitleFontSize"),
                ("Ticks", "tickLabelFontSize"),
                ("Legend","legendFontSize"),
            ], id: \.1) { label, key in
                fontSizePicker(label: label, key: key)
            }
        }
    }

    @ViewBuilder
    private func fontSizePicker(label: String, key: String) -> some View {
        let defaultSize: CGFloat = WorkbenchChartStyle()[keyPath: Self.fontSizeKeyPath(key)]
        let current = chartStyleOverrides[key].flatMap { Double($0).map { CGFloat($0) } } ?? defaultSize
        HStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
            Picker("", selection: Binding<CGFloat>(
                get: { current },
                set: { newVal in
                    chartStyleOverrides[key] = "\(Int(newVal))"
                    onStyleChange?()
                }
            )) {
                ForEach(_plotControlsFontSizeOptions, id: \.self) { s in
                    Text("\(Int(s))").tag(s)
                }
            }
            .labelsHidden()
            .frame(width: 58)
        }
    }

    @ViewBuilder
    private func tickDensityStepper(label: String, key: String, fallback: Int) -> some View {
        let current = chartStyleOverrides[key].flatMap { Int($0) } ?? fallback
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
            Stepper(
                value: Binding<Int>(
                    get: { current },
                    set: { newVal in
                        chartStyleOverrides[key] = "\(newVal)"
                        onStyleChange?()
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
        case "legendFontSize":    return \.legendFontSize
        default:                  return \.titleFontSize
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
