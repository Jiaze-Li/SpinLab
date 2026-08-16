import Foundation

/// Marks a workflow store as a full participant in the standard (stacked-curve) Cartesian
/// XY plot controls surface — the shape shared by AHE, IV, RT, and XY Rotation.
///
/// Conforming stores expose everything `WorkbenchStandardPlotControls` needs to derive its
/// ~25 value/binding inputs from `store` alone, via the `init(store:...)` overload in
/// `WorkbenchStandardPlotControls+StoreDriven.swift`. Two fields — `canReorderSeries` and
/// the current series order — are deliberately NOT derived here and stay explicit call-site
/// parameters: AHE's `WorkbenchWorkspaceProviding` conformance relies on the protocol's
/// default `canReorderSeries { false }` / `activeSeriesOrder { nil }` (its concrete
/// reordering state lives only in `tabs.activeState.seriesOrder`), so folding those two
/// through this protocol would silently disable AHE's series drag-reorder. RSM and 3ω are
/// intentionally excluded — see `docs/architecture/workbench/modules/PLOT_SYSTEM.md`.
@MainActor
protocol WorkbenchStandardPlotWorkspaceStore: WorkbenchWorkspaceProviding, WorkbenchCartesianXYPlottingStore {
    associatedtype PlotTab: CaseIterable & Hashable & Identifiable where PlotTab.AllCases: RandomAccessCollection

    var tabs: TabRenderManager<PlotTab> { get }
    var titleTemplate: String { get set }
    var stackOffsetMultiplier: Double { get set }
    var minGapFraction: Double { get set }

    func resetAxisRanges()
    func updateAxisBound(_ bound: AxisRangeBound, value: Double?)
    func updateTickCount(axis: PlotTickAxis, count: Int)
}

extension AHEWorkspaceStore: WorkbenchStandardPlotWorkspaceStore {}
extension IVWorkspaceStore: WorkbenchStandardPlotWorkspaceStore {}
extension RTWorkspaceStore: WorkbenchStandardPlotWorkspaceStore {}
extension XYRotationWorkspaceStore: WorkbenchStandardPlotWorkspaceStore {}
