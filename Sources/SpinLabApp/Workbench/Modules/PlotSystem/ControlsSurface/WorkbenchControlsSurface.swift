import SwiftUI

/// The Plot-Mode choice plus its state adapter. Naming the case *is* declaring the mode,
/// so a workflow cannot mount a Plot section without a valid mode (CS-1, CS-17).
enum WorkbenchControlsPlotAdapter {
    case cartesianXY(CartesianXYControlsModel)
    case dualAxis(DualAxisControlsModel)
    case heatmap(HeatmapControlsModel)

    var mode: WorkbenchPlotMode {
        switch self {
        case .cartesianXY: return .cartesianXY
        case .dualAxis: return .dualAxis
        case .heatmap: return .heatmap
        }
    }
}

/// Everything a workflow contributes to its controls (CS-1): a Common model, a Plot
/// adapter and optional Specific content. Nothing here describes layout.
struct WorkbenchControlsDescriptor {
    var common: WorkbenchCommonControlsModel
    var plot: WorkbenchControlsPlotAdapter
    var specific: WorkbenchSpecificContent = .empty
}

/// The one view that renders a workflow's controls: Common → Plot → Specific (CS-2).
struct WorkbenchControlsSurface: View {
    let descriptor: WorkbenchControlsDescriptor

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: WorkbenchControlMetrics.lineSpacing) {
                WorkbenchCommonControls(model: descriptor.common)
                Divider()
                plotSection
                if !descriptor.specific.isEmpty {
                    Divider()
                    WorkbenchSpecificSection(content: descriptor.specific)
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .coordinateSpace(name: WorkbenchControlMetrics.coordinateSpaceName)
        }
        .accessibilityIdentifier("controls.surface.\(descriptor.plot.mode.rawValue)")
    }

    @ViewBuilder
    private var plotSection: some View {
        switch descriptor.plot {
        case .cartesianXY(let model): CartesianXYPlotControls(model: model)
        case .dualAxis(let model): DualAxisPlotControls(model: model)
        case .heatmap(let model): HeatmapPlotControls(model: model)
        }
    }
}
