import Foundation

/// The closed set of plot families the Controls Surface can assemble.
///
/// A workflow declares which of these it renders; the Surface owns the control list,
/// order and layout for each. Adding a case requires a shared Plot component and its
/// contract tests first — see `specs/06_WORKBENCH_CONTROLS_UI.md` (CS-14).
enum WorkbenchPlotMode: String, CaseIterable, Hashable {
    case cartesianXY
    case dualAxis
    case heatmap
}

/// Typed Plot-Family capabilities (CS-12a). Presence of a capability — never a workflow
/// identity — is the only thing that may add conditional content to a Plot section.
struct CartesianXYCapabilities: OptionSet, Hashable {
    let rawValue: Int
    /// Adds a Point Tags checkbox to the Title Template group.
    static let pointTags = CartesianXYCapabilities(rawValue: 1 << 0)
}
