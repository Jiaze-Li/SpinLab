import Foundation

/// Explicit overlay contract for Plot System charts.
///
/// Overlays are display-faithful series that are anchored to a parent measurement
/// series by identity. They are not part of legend inference, series reorder, or
/// stacking calculations, but they do inherit the parent's final display visibility
/// and stack offset.
struct WorkbenchPlotSeriesOverlay: Hashable, Sendable {
    /// Stable overlay identity for persistence and diffing.
    var overlayIdentityKey: String
    /// Stable parent-series identity key from the base series collection.
    var parentSeriesIdentityKey: String
    /// The overlay's own rendered series data.
    var series: WorkbenchPlotSeries
    /// Optional display-resolved overlay series. When present, renderers use this series
    /// instead of `series` so the overlay can inherit its parent's final visibility and
    /// stack offset without mutating the raw overlay payload.
    var displaySeries: WorkbenchPlotSeries? = nil

    init(
        overlayIdentityKey: String,
        parentSeriesIdentityKey: String,
        series: WorkbenchPlotSeries,
        displaySeries: WorkbenchPlotSeries? = nil
    ) {
        self.overlayIdentityKey = overlayIdentityKey
        self.parentSeriesIdentityKey = parentSeriesIdentityKey
        self.series = series
        self.displaySeries = displaySeries
    }
}

extension WorkbenchPlotSeriesOverlay: Codable {
    private enum CodingKeys: String, CodingKey {
        case overlayIdentityKey
        case parentSeriesIdentityKey
        case series
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overlayIdentityKey = try c.decode(String.self, forKey: .overlayIdentityKey)
        parentSeriesIdentityKey = try c.decode(String.self, forKey: .parentSeriesIdentityKey)
        series = try c.decode(WorkbenchPlotSeries.self, forKey: .series)
        displaySeries = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(overlayIdentityKey, forKey: .overlayIdentityKey)
        try c.encode(parentSeriesIdentityKey, forKey: .parentSeriesIdentityKey)
        try c.encode(series, forKey: .series)
    }
}

enum WorkbenchPlotSeriesOverlayResolver {
    static func resolve(
        overlays: [WorkbenchPlotSeriesOverlay],
        baseSeries: [WorkbenchPlotSeries],
        displayOffsetsByIdentityKey: [String: Double],
        hiddenSeriesKeys: Set<String> = []
    ) -> [WorkbenchPlotSeriesOverlay] {
        guard !overlays.isEmpty else { return [] }
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: baseSeries)
        let visibleByIdentity = Dictionary(uniqueKeysWithValues: identities.map { ($0.identityKey, $0.originalIndex) })

        return overlays.compactMap { overlay in
            guard let parentIndex = visibleByIdentity[overlay.parentSeriesIdentityKey],
                  let parentOffset = displayOffsetsByIdentityKey[overlay.parentSeriesIdentityKey] else {
                return nil
            }
            guard !hiddenSeriesKeys.contains(overlay.parentSeriesIdentityKey) else {
                return nil
            }
            var resolved = overlay
            var displaySeries = overlay.series
            displaySeries.y = displaySeries.y.map { $0 + parentOffset }
            if let parent = baseSeries[safe: parentIndex] {
                displaySeries.renderMode = overlay.series.renderMode
                displaySeries.lineWidth = overlay.series.lineWidth
                displaySeries.pointLabels = overlay.series.pointLabels
                displaySeries.sourceRef = overlay.series.sourceRef ?? parent.sourceRef
                displaySeries.sampleID = overlay.series.sampleID ?? parent.sampleID
            }
            resolved.displaySeries = displaySeries
            return resolved
        }
    }
}
