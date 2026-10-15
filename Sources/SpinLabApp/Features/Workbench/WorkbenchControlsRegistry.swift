import Foundation

/// How a workflow's controls are mounted. `.legacy` is the bounded migration path listed in
/// `scripts/controls_contract_legacy_allowlist.txt`; it is removed once every workflow is on
/// the Surface (spec §10).
enum WorkbenchControlsMount: Equatable {
    case surface
    case legacy
}

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

    /// Exhaustive mount declaration. New workflows must be `.surface`; `.legacy` is only
    /// accepted for the grandfathered entries in the allow-list.
    var controlsMount: WorkbenchControlsMount {
        switch self {
        case .ahe, .iv, .rt, .xyRotation, .threeOmega, .rsm, .afm: return .legacy
        }
    }
}
