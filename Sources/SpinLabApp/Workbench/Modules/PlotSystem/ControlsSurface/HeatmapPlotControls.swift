import SwiftUI

/// State and callbacks of the `heatmap` Plot section (CS-28). The Heatmap-specific modules are
/// identical for AFM and RSM; Typography and Axes follow the typed capability configuration
/// (`fontRoles`, `axes`): an axis-free figure declares only the title font and no axes (CS-15).
struct HeatmapControlsModel {
    var colorScaleMode: PlotScaleTransform
    var interpolationMode: HeatmapInterpolationMode
    var zDomainState: HeatmapZDomainState
    var showColorbar: Bool
    var globalPlotDefaults: Binding<[String: String]>
    var fontRoles: [PlotFontRole] = [.title]
    var axes: PlotAxesModel
    var onStyleChange: () -> Void
    var onColorScaleModeChange: (PlotScaleTransform) -> Void
    var onInterpolationModeChange: (HeatmapInterpolationMode) -> Void
    var onZDomainStateChange: (HeatmapZDomainState) -> Void
    var onShowColorbarChange: (Bool) -> Void
}

/// The single `heatmap` Plot section (CS-11): Color Scale · Interpolation · Colorbar · Z Range,
/// plus the Shared Typography and Axes modules for the declared capability configuration.
struct HeatmapPlotControls: View {
    let model: HeatmapControlsModel
    private let id = "controls.plot"

    private var z: HeatmapZDomainState { model.zDomainState }

    var body: some View {
        WorkbenchControlFlow(justified: true) {
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
                WorkbenchCheckbox(title: "Colorbar", isOn: Binding(get: { model.showColorbar }, set: { model.onShowColorbarChange($0) }))
            }
            WorkbenchControlGroup(id: "\(id).interpolation") {
                WorkbenchControlRow(id: "\(id).interpolation.mode", label: "Interpolation") {
                    Picker("", selection: Binding(get: { model.interpolationMode }, set: { model.onInterpolationModeChange($0) })) {
                        Text(HeatmapInterpolationMode.nearest.controlTitle).tag(HeatmapInterpolationMode.nearest)
                        Text(HeatmapInterpolationMode.logSpaceGaussian1p5x.controlTitle).tag(HeatmapInterpolationMode.logSpaceGaussian1p5x)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: WorkbenchInputWidth.standard, idealWidth: WorkbenchInputWidth.interpolationMenu,
                           maxWidth: WorkbenchInputWidth.interpolationMenu, alignment: .leading)
                    .workbenchControl(.menu)
                    .help(model.interpolationMode.fullName)
                    .accessibilityValue(model.interpolationMode.fullName)
                }
            }
            zRangeGroup.workbenchFlowFill()
            PlotAxesControls(model: model.axes, idPrefix: id)
            PlotTypographyControls(
                globalPlotDefaults: model.globalPlotDefaults,
                roles: model.fontRoles,
                onStyleChange: model.onStyleChange,
                idPrefix: id
            )
        }
        .onAppear(perform: normalizeCustomPercentilePresetIfNeeded)
        .onChange(of: z.mode) { _, _ in normalizeCustomPercentilePresetIfNeeded() }
        .onChange(of: z.percentilePreset) { _, _ in normalizeCustomPercentilePresetIfNeeded() }
    }

    private var zRangeGroup: some View {
        WorkbenchControlGroup(id: "\(id).zRange") {
            switch z.mode {
            case .auto:
                zModeRow
            case .manual:
                zModeRow
                WorkbenchControlRow(id: "\(id).zRange.manual", label: "Min / Max") {
                    WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                        zField("Min", z.manualRange.minText) { var n = z; n.manualRange.minText = $0; model.onZDomainStateChange(n) }
                        zField("Max", z.manualRange.maxText) { var n = z; n.manualRange.maxText = $0; model.onZDomainStateChange(n) }
                    }
                }
            case .percentile:
                // The Preset belongs to the mode: beside it while it fits, otherwise on the next line.
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    zModeRow
                    zPresetRow
                }
            }
            if let issue = z.validationIssue() {
                Text(issue.message)
                    .font(WorkbenchUIStyle.controlValueFont)
                    .foregroundStyle(WorkbenchUIStyle.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var zModeRow: some View {
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
    }

    private var zPresetRow: some View {
        WorkbenchControlRow(id: "\(id).zRange.preset", label: "Preset") {
            Picker("", selection: Binding<HeatmapPercentilePreset>(
                get: { z.percentilePreset == .custom ? .p1_99 : z.percentilePreset },
                set: { preset in var n = z; n.percentilePreset = preset; model.onZDomainStateChange(n) }
            )) {
                ForEach(HeatmapPercentilePreset.visiblePresets, id: \.self) { Text($0.displayTitle).tag($0) }
            }
            .labelsHidden()
            .frame(minWidth: WorkbenchInputWidth.standard, idealWidth: WorkbenchInputWidth.percentilePresetMenu,
                   maxWidth: WorkbenchInputWidth.percentilePresetMenu, alignment: .leading)
            .workbenchControl(.menu)
        }
    }

    private func zField(_ label: String, _ value: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(WorkbenchUIStyle.controlLabelFont).fixedSize()
            TextField("", text: Binding(get: { value }, set: set))
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: WorkbenchInputWidth.standard, maxWidth: WorkbenchInputWidth.standard)
                .workbenchControl(.textField)
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

extension HeatmapInterpolationMode {
    /// Compact menu text; the scientific name is `fullName` (tooltip and accessibility value).
    var controlTitle: String {
        switch self {
        case .nearest: return "Nearest"
        case .logSpaceGaussian1p5x: return "Log-Gauss 1.5×"
        }
    }

    var fullName: String {
        switch self {
        case .nearest: return "Nearest"
        case .logSpaceGaussian1p5x: return "Log-Space Gaussian 1.5×"
        }
    }
}
