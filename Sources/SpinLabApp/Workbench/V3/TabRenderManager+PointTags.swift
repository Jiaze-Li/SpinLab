import Foundation

// MARK: - TabRenderManager point tag interface

extension TabRenderManager {

    /// Sets the global point tag visibility toggle for the active tab.
    func setShowPointTags(_ show: Bool) {
        tabStates[activeTab, default: TabRenderState()].pointTags.showPointTags = show
    }

    /// Toggles visibility of a single point label on the active tab.
    /// Key is sampleID (preferred) or legacy Int-string fallback.
    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        tabStates[activeTab, default: TabRenderState()].pointTags.toggleVisibility(
            sampleID: sampleID, pointIndex: pointIndex
        )
    }

    /// Returns the hidden-point-label indices for a given tab, keyed by sampleID or Int-string.
    func hiddenPointLabelsBySampleID(for tab: Tab) -> [String: [Int]] {
        (tabStates[tab] ?? TabRenderState()).pointTags.hiddenPointLabelIndicesBySeries
    }
}
