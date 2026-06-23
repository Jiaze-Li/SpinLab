import Foundation

// MARK: - PointTagState

/// Point tag visibility state for a single Workbench tab.
///
/// Groups the two point-tag fields from TabRenderState behind a named boundary so
/// callers can work with the capability as a unit. The underlying stored properties
/// remain on TabRenderState as flat JSON keys, preserving Codable backward compatibility.
///
/// A workflow opts in to point tags by populating `WorkbenchPlotSeries.pointLabels`.
/// The UI toggle (`showPointTags`) and per-point hide state (`hiddenPointLabelIndicesBySeries`)
/// are both no-ops for series with empty `pointLabels`.
struct PointTagState: Hashable, Sendable {
    var showPointTags: Bool = false
    /// Per-series hidden point indices. Key: sampleID (preferred) or legacy Int-string.
    var hiddenPointLabelIndicesBySeries: [String: [Int]] = [:]

    init(
        showPointTags: Bool = false,
        hiddenPointLabelIndicesBySeries: [String: [Int]] = [:]
    ) {
        self.showPointTags = showPointTags
        self.hiddenPointLabelIndicesBySeries = hiddenPointLabelIndicesBySeries
    }

    /// Toggles visibility of a single point label. Adds the index on first call; removes it on second.
    mutating func toggleVisibility(sampleID: String, pointIndex: Int) {
        var indices = Set(hiddenPointLabelIndicesBySeries[sampleID] ?? [])
        if indices.contains(pointIndex) {
            indices.remove(pointIndex)
        } else {
            indices.insert(pointIndex)
        }
        hiddenPointLabelIndicesBySeries[sampleID] = indices.isEmpty ? nil : indices.sorted()
    }
}

// MARK: - TabRenderState point tag accessor

extension TabRenderState {
    /// Grouped read/write accessor for point tag state.
    ///
    /// Backed by the stored `showPointTags` and `hiddenPointLabelIndicesBySeries` properties
    /// so JSON encoding stays flat and Codable compatibility is preserved.
    var pointTags: PointTagState {
        get {
            PointTagState(
                showPointTags: showPointTags,
                hiddenPointLabelIndicesBySeries: hiddenPointLabelIndicesBySeries
            )
        }
        set {
            showPointTags = newValue.showPointTags
            hiddenPointLabelIndicesBySeries = newValue.hiddenPointLabelIndicesBySeries
        }
    }
}
