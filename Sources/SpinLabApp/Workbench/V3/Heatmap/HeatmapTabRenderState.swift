import Foundation

/// Per-tab heatmap display override state (Plot System-owned, Plot Preservation).
/// Parallel structure to TabRenderState — must not extend or inherit from it.
/// XY-specific fields (seriesOrder, legendPoint, seriesLabelOverrides, hiddenPointLabels)
/// have no meaning for heatmap tabs and are absent.
struct HeatmapTabRenderState: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = Self.currentSchemaVersion
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    /// Colorbar label override (Z-axis title).
    var zLabelOverride: String = ""
    var colorScaleMode: HeatmapColorScaleMode = .linear
    var colormapKey: String = "viridis"
    var zDomainState: HeatmapZDomainState = .init()

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        zLabelOverride: String = "",
        colorScaleMode: HeatmapColorScaleMode = .linear,
        colormapKey: String = "viridis",
        zDomainState: HeatmapZDomainState = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.titleOverride  = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.zLabelOverride = zLabelOverride
        self.colorScaleMode = colorScaleMode
        self.colormapKey = colormapKey
        self.zDomainState = zDomainState
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case titleOverride
        case xLabelOverride
        case yLabelOverride
        case zLabelOverride
        case colorScaleMode
        case colormapKey
        case zDomainState
        case zRangeOverrideMin
        case zRangeOverrideMax
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        xLabelOverride = try c.decodeIfPresent(String.self, forKey: .xLabelOverride) ?? ""
        yLabelOverride = try c.decodeIfPresent(String.self, forKey: .yLabelOverride) ?? ""
        zLabelOverride = try c.decodeIfPresent(String.self, forKey: .zLabelOverride) ?? ""
        colorScaleMode = try c.decodeIfPresent(HeatmapColorScaleMode.self, forKey: .colorScaleMode) ?? .linear
        colormapKey = try c.decodeIfPresent(String.self, forKey: .colormapKey) ?? "viridis"

        if let decodedDomain = try c.decodeIfPresent(HeatmapZDomainState.self, forKey: .zDomainState) {
            zDomainState = decodedDomain
        } else if
            let legacyMin = try c.decodeIfPresent(Double.self, forKey: .zRangeOverrideMin),
            let legacyMax = try c.decodeIfPresent(Double.self, forKey: .zRangeOverrideMax),
            legacyMin.isFinite,
            legacyMax.isFinite,
            legacyMin < legacyMax
        {
            zDomainState = HeatmapZDomainState(
                mode: .manual,
                manualRange: HeatmapZRangeDraft(minText: "\(legacyMin)", maxText: "\(legacyMax)")
            )
        } else {
            zDomainState = .init()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(titleOverride, forKey: .titleOverride)
        try c.encode(xLabelOverride, forKey: .xLabelOverride)
        try c.encode(yLabelOverride, forKey: .yLabelOverride)
        try c.encode(zLabelOverride, forKey: .zLabelOverride)
        try c.encode(colorScaleMode, forKey: .colorScaleMode)
        try c.encode(colormapKey, forKey: .colormapKey)
        try c.encode(zDomainState, forKey: .zDomainState)

        if zDomainState.mode == .manual,
           let resolved = zDomainState.resolve(rawValues: []).resolvedBounds {
            try c.encode(resolved.lowerBound, forKey: .zRangeOverrideMin)
            try c.encode(resolved.upperBound, forKey: .zRangeOverrideMax)
        }
    }
}
