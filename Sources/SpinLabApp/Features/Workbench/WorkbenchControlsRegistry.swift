import SwiftUI

extension WorkbenchWorkflowKind {
    /// Plot modes this workflow can render. Exhaustive: a new workflow must declare at
    /// least one valid mode or it does not compile (AC7).
    var controlsPlotModes: Set<WorkbenchPlotMode> {
        switch self {
        case .ahe, .iv, .rt, .xyRotation: return [.cartesianXY]
        case .threeOmega: return [.cartesianXY, .dualAxis]
        case .rsm, .afm: return [.heatmap]
        }
    }

    /// The workflow's Controls Surface descriptor, built by its adapter. Exhaustive: a new
    /// workflow must supply an adapter here or it does not compile, and the only thing an
    /// adapter can return is a descriptor for the shared Surface (AC7).
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        let workbench = appState.workbench
        switch self {
        case .ahe: return workbench.aheWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        case .iv: return workbench.ivWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        case .rt: return workbench.rtWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        case .xyRotation: return workbench.xyRotationWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        case .threeOmega: return workbench.threeOmegaWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        case .rsm: return workbench.rsmWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        case .afm: return workbench.afmWorkspace.controlsDescriptor(appState: appState, globalPlotDefaults: globalPlotDefaults)
        }
    }
}
