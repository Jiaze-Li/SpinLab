import SwiftUI

/// State and callbacks of the `heatmap` Plot section (CS-28): exactly the controls valid
/// for every heatmap workflow (AFM and RSM alike).
struct HeatmapControlsModel {
    var colorScaleMode: PlotScaleTransform
    var interpolationMode: HeatmapInterpolationMode
    var zDomainState: HeatmapZDomainState
    var showColorbar: Bool
    var onColorScaleModeChange: (PlotScaleTransform) -> Void
    var onInterpolationModeChange: (HeatmapInterpolationMode) -> Void
    var onZDomainStateChange: (HeatmapZDomainState) -> Void
    var onShowColorbarChange: (Bool) -> Void
}

/// The single `heatmap` Plot section (CS-11): Color Scale · Interpolation · Colorbar · Z Range.
struct HeatmapPlotControls: View {
    let model: HeatmapControlsModel
    private let id = "controls.plot"

    private var z: HeatmapZDomainState { model.zDomainState }

    var body: some View {
        WorkbenchControlFlow {
            WorkbenchControlGroup(id: "\(id).colorScale") {
                WorkbenchControlRow(id: "\(id).colorScale.mode", label: "Color scale") {
                    Picker("", selection: Binding(get: { model.colorScaleMode }, set: { model.onColorScaleModeChange($0) })) {
                        Text("Linear").tag(PlotScaleTransform.linear)
                        Text("Log").tag(PlotScaleTransform.log10)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(minWidth: 96, maxWidth: 160)
                }
            }
            WorkbenchControlGroup(id: "\(id).colorbar") {
                Toggle("Colorbar", isOn: Binding(get: { model.showColorbar }, set: { model.onShowColorbarChange($0) }))
                    .toggleStyle(.checkbox)
            }
            WorkbenchControlGroup(id: "\(id).interpolation") {
                WorkbenchControlRow(id: "\(id).interpolation.mode", label: "Interpolation") {
                    Picker("", selection: Binding(get: { model.interpolationMode }, set: { model.onInterpolationModeChange($0) })) {
                        Text("Nearest").tag(HeatmapInterpolationMode.nearest)
                        Text("Log-Space Gaussian 1.5×").tag(HeatmapInterpolationMode.logSpaceGaussian1p5x)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                }
            }
            zRangeGroup.workbenchFlowFill()
        }
        .onAppear(perform: normalizeCustomPercentilePresetIfNeeded)
        .onChange(of: z.mode) { _, _ in normalizeCustomPercentilePresetIfNeeded() }
        .onChange(of: z.percentilePreset) { _, _ in normalizeCustomPercentilePresetIfNeeded() }
    }

    private var zRangeGroup: some View {
        WorkbenchControlGroup(id: "\(id).zRange") {
            WorkbenchControlRow(id: "\(id).zRange.mode", label: "Z range") {
                Picker("", selection: Binding<HeatmapZDomainMode>(
                    get: { z.mode },
                    set: { mode in var next = z; next.mode = mode; model.onZDomainStateChange(next) }
                )) {
                    Text("Auto").tag(HeatmapZDomainMode.auto)
                    Text("Manual").tag(HeatmapZDomainMode.manual)
                    Text("Percentile").tag(HeatmapZDomainMode.percentile)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(minWidth: 140, maxWidth: 280)
            }
            switch z.mode {
            case .auto:
                EmptyView()
            case .manual:
                WorkbenchControlRow(id: "\(id).zRange.manual", label: "Min / Max") {
                    WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                        zField("Min", z.manualRange.minText) { var n = z; n.manualRange.minText = $0; model.onZDomainStateChange(n) }
                        zField("Max", z.manualRange.maxText) { var n = z; n.manualRange.maxText = $0; model.onZDomainStateChange(n) }
                    }
                }
            case .percentile:
                WorkbenchControlRow(id: "\(id).zRange.preset", label: "Preset") {
                    Picker("", selection: Binding<HeatmapPercentilePreset>(
                        get: { z.percentilePreset == .custom ? .p1_99 : z.percentilePreset },
                        set: { preset in var n = z; n.percentilePreset = preset; model.onZDomainStateChange(n) }
                    )) {
                        ForEach(HeatmapPercentilePreset.visiblePresets, id: \.self) { Text($0.displayTitle).tag($0) }
                    }
                    .labelsHidden()
                    .frame(minWidth: 96, maxWidth: 240, alignment: .leading)
                }
            }
            if let issue = z.validationIssue() {
                Text(issue.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zField(_ label: String, _ value: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(WorkbenchUIStyle.controlLabelFont).fixedSize()
            TextField("", text: Binding(get: { value }, set: set))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: WorkbenchInputWidth.standard, maxWidth: WorkbenchInputWidth.standard)
                .accessibilityLabel("Z \(label.lowercased())")
        }
    }

    private func normalizeCustomPercentilePresetIfNeeded() {
        guard z.mode == .percentile, z.percentilePreset == .custom else { return }
        var next = z
        next.percentilePreset = .p1_99
        model.onZDomainStateChange(next)
    }
}
