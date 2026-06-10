import Foundation
import Observation

/// Common runtime that owns session-level overlay display and control state.
///
/// This runtime is deliberately workflow-agnostic. It knows nothing about RAHE, Scaling Law,
/// OverlaySnapshot content, sample-key policy, metric definitions, or rendered curve data.
///
/// The 3ω workspace delegates overlay ID list and chip display state here.
/// It retains OverlaySnapshot content (sweeps, sampleKeys, sourceFiles) and all
/// rendering semantics itself.
///
/// Gate 7.4 first cut: session-only. Overlay state is never serialized.
@MainActor
@Observable
final class WorkbenchAnalysisOverlayRuntime {

    // MARK: - State (session-only, never serialized)

    /// Ordered list of active overlay pack IDs.
    private(set) var overlayIDs: [AnalysisPack.ID] = []

    /// Display label per active overlay entry (used by chip UI).
    private(set) var displayLabels: [AnalysisPack.ID: String] = [:]

    // MARK: - Operations

    /// Register an overlay entry. Called by the workflow after it has successfully
    /// decoded the pack and built its own typed snapshot. Idempotent: a second call
    /// with the same id is silently ignored.
    func addEntry(id: AnalysisPack.ID, label: String) {
        guard !overlayIDs.contains(id) else { return }
        overlayIDs.append(id)
        displayLabels[id] = label
    }

    /// Remove an overlay entry. Called by the workflow's removeOverlay method.
    func removeEntry(id: AnalysisPack.ID) {
        overlayIDs.removeAll { $0 == id }
        displayLabels.removeValue(forKey: id)
    }

    /// Clear all overlay state. Called on pack restore and clearPlot.
    func clear() {
        overlayIDs = []
        displayLabels = [:]
    }

    /// Returns true if the given pack ID is currently overlaid.
    func isOverlaid(_ id: AnalysisPack.ID) -> Bool {
        overlayIDs.contains(id)
    }
}
