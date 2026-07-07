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
    /// Whether the colorbar block (gradient, tick labels, Z title) is shown.
    var showColorbar: Bool = true
    var colorScaleMode: HeatmapColorScaleMode = .linear
    /// Explicit user colormap override. Nil = no override (defer to payload.colormapKey /
    /// workflow default / viridis fallback). Must not default to "viridis" — that would
    /// make every payload's colormap indistinguishable from "user chose viridis".
    var colormapKey: String? = nil
    var zDomainState: HeatmapZDomainState = .init()
    /// Shared tick count configuration for X and Y axes.
    var tickConfiguration: PlotTickConfiguration = .defaultValue
    /// Display-only grid interpolation. Defaults to nearest (scientifically safer, blockier).
    /// Gaussian Upsample 2x is an opt-in for publication/export — never applied to stored scientific data.
    var interpolationMode: HeatmapInterpolationMode = .nearest

    /// Backward-compatible accessor for the X-axis target tick count.
    var xTickCount: Int {
        get { tickConfiguration.xTargetCount }
        set { tickConfiguration.xTargetCount = PlotTickConfiguration.clamp(newValue) }
    }

    /// Backward-compatible accessor for the Y-axis target tick count.
    var yTickCount: Int {
        get { tickConfiguration.yTargetCount }
        set { tickConfiguration.yTargetCount = PlotTickConfiguration.clamp(newValue) }
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        zLabelOverride: String = "",
        showColorbar: Bool = true,
        colorScaleMode: HeatmapColorScaleMode = .linear,
        colormapKey: String? = nil,
        zDomainState: HeatmapZDomainState = .init(),
        xTickCount: Int = 5,
        yTickCount: Int = 5,
        interpolationMode: HeatmapInterpolationMode = .nearest
    ) {
        self.schemaVersion = schemaVersion
        self.titleOverride  = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.zLabelOverride = zLabelOverride
        self.showColorbar = showColorbar
        self.colorScaleMode = colorScaleMode
        self.colormapKey = colormapKey
        self.zDomainState = zDomainState
        self.tickConfiguration = PlotTickConfiguration(xTargetCount: xTickCount, yTargetCount: yTickCount)
        self.interpolationMode = interpolationMode
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case titleOverride
        case xLabelOverride
        case yLabelOverride
        case zLabelOverride
        case showColorbar
        case showZLabel       // legacy key — decoded only, not encoded
        case colorScaleMode
        case colormapKey
        case zDomainState
        case tickConfiguration
        case xTickCount       // legacy key — decoded only, not encoded
        case yTickCount       // legacy key — decoded only, not encoded
        case zRangeOverrideMin
        case zRangeOverrideMax
        case interpolationMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        xLabelOverride = try c.decodeIfPresent(String.self, forKey: .xLabelOverride) ?? ""
        yLabelOverride = try c.decodeIfPresent(String.self, forKey: .yLabelOverride) ?? ""
        zLabelOverride = try c.decodeIfPresent(String.self, forKey: .zLabelOverride) ?? ""

        // showColorbar supersedes legacy showZLabel; both default to true
        if let v = try c.decodeIfPresent(Bool.self, forKey: .showColorbar) {
            showColorbar = v
        } else if let v = try c.decodeIfPresent(Bool.self, forKey: .showZLabel) {
            showColorbar = v
        } else {
            showColorbar = true
        }

        colorScaleMode = try c.decodeIfPresent(HeatmapColorScaleMode.self, forKey: .colorScaleMode) ?? .linear
        // Nil (absent or null) means "no override" — legacy packs without this key must not
        // be forced onto viridis, since that would silently mask a payload's own colormapKey.
        colormapKey = try c.decodeIfPresent(String.self, forKey: .colormapKey)

        // New packs encode tickConfiguration directly; old packs use legacy xTickCount/yTickCount keys.
        if let tc = try c.decodeIfPresent(PlotTickConfiguration.self, forKey: .tickConfiguration) {
            tickConfiguration = tc
        } else {
            tickConfiguration = PlotTickConfiguration(
                xTargetCount: try c.decodeIfPresent(Int.self, forKey: .xTickCount) ?? PlotTickConfiguration.defaultValue.xTargetCount,
                yTargetCount: try c.decodeIfPresent(Int.self, forKey: .yTickCount) ?? PlotTickConfiguration.defaultValue.yTargetCount
            )
        }

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

        // Old packs predating this field must default to nearest — the scientifically
        // safer, non-smoothing option — never silently opt them into gaussianUpsample2x.
        interpolationMode = try c.decodeIfPresent(HeatmapInterpolationMode.self, forKey: .interpolationMode) ?? .nearest
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(titleOverride, forKey: .titleOverride)
        try c.encode(xLabelOverride, forKey: .xLabelOverride)
        try c.encode(yLabelOverride, forKey: .yLabelOverride)
        try c.encode(zLabelOverride, forKey: .zLabelOverride)
        try c.encode(showColorbar, forKey: .showColorbar)
        try c.encode(colorScaleMode, forKey: .colorScaleMode)
        try c.encode(colormapKey, forKey: .colormapKey)
        try c.encode(zDomainState, forKey: .zDomainState)
        try c.encode(tickConfiguration, forKey: .tickConfiguration)
        try c.encode(interpolationMode, forKey: .interpolationMode)

        if zDomainState.mode == .manual,
           let resolved = zDomainState.resolve(rawValues: []).resolvedBounds {
            try c.encode(resolved.lowerBound, forKey: .zRangeOverrideMin)
            try c.encode(resolved.upperBound, forKey: .zRangeOverrideMax)
        }
    }
}
