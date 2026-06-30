import Foundation

// MARK: - DualAxis color/style primitives

/// Template color roles for the DualAxis render path.
/// These are display roles only; they must not encode workflow physics.
enum DualAxisColorRole: String, Codable, Hashable, Sendable, CaseIterable {
    case leftAxisBlue
    case rightAxisRed
    case black
    case gray
    case green
    case orange
    case purple
    case teal
}

/// Whether the renderer visually pairs the left/right axis colors with the left/right series.
enum DualAxisAxisColorPolicy: String, Codable, Hashable, Sendable, CaseIterable {
    case templatePaired
    case monochrome
}

enum DualAxisLinePattern: String, Codable, Hashable, Sendable, CaseIterable {
    case solid
    case dashed
}

enum DualAxisMarkerShape: String, Codable, Hashable, Sendable, CaseIterable {
    case circle
    case square
}

enum DualAxisMarkerFill: String, Codable, Hashable, Sendable, CaseIterable {
    case filled
    case open
}

/// Generic visual style for one DualAxis series family.
/// Values are display-state knobs and are not workflow semantics.
struct DualAxisSeriesVisualStyle: Codable, Hashable, Sendable {
    var renderMode: SeriesRenderMode?
    var lineWidth: Double?
    var pointRadius: Double?
    var linePattern: DualAxisLinePattern
    var markerShape: DualAxisMarkerShape
    var markerFill: DualAxisMarkerFill
    var colorRole: DualAxisColorRole?

    init(
        renderMode: SeriesRenderMode? = nil,
        lineWidth: Double? = nil,
        pointRadius: Double? = nil,
        linePattern: DualAxisLinePattern = .solid,
        markerShape: DualAxisMarkerShape = .circle,
        markerFill: DualAxisMarkerFill = .filled,
        colorRole: DualAxisColorRole? = nil
    ) {
        self.renderMode = renderMode
        self.lineWidth = lineWidth
        self.pointRadius = pointRadius
        self.linePattern = linePattern
        self.markerShape = markerShape
        self.markerFill = markerFill
        self.colorRole = colorRole
    }

    static let leftTemplate = DualAxisSeriesVisualStyle(
        linePattern: .solid,
        markerShape: .square,
        markerFill: .open,
        colorRole: .leftAxisBlue
    )

    static let rightTemplate = DualAxisSeriesVisualStyle(
        linePattern: .dashed,
        markerShape: .circle,
        markerFill: .filled,
        colorRole: .rightAxisRed
    )
}

// MARK: - DualAxis axis ranges

/// Manual range overrides for a DualAxis chart. nil bounds use the auto range.
struct DualAxisAxisRangeOverride: Codable, Hashable, Sendable {
    var xMin: Double?
    var xMax: Double?
    var leftYMin: Double?
    var leftYMax: Double?
    var rightYMin: Double?
    var rightYMax: Double?

    init(
        xMin: Double? = nil,
        xMax: Double? = nil,
        leftYMin: Double? = nil,
        leftYMax: Double? = nil,
        rightYMin: Double? = nil,
        rightYMax: Double? = nil
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.leftYMin = leftYMin
        self.leftYMax = leftYMax
        self.rightYMin = rightYMin
        self.rightYMax = rightYMax
    }

    var isEmpty: Bool {
        xMin == nil && xMax == nil &&
        leftYMin == nil && leftYMax == nil &&
        rightYMin == nil && rightYMax == nil
    }
}

enum DualAxisAxisRangeBound: Sendable {
    case xMin, xMax, leftYMin, leftYMax, rightYMin, rightYMax
}

/// Pure reducer used by DualAxis controls. Invalid finite pairs are rejected without mutating state.
func dualAxisRangeOverrideByUpdating(
    _ current: DualAxisAxisRangeOverride?,
    bound: DualAxisAxisRangeBound,
    value: Double?
) -> DualAxisAxisRangeOverride? {
    if let value, !value.isFinite { return current }

    var next = current ?? DualAxisAxisRangeOverride()
    switch bound {
    case .xMin:      next.xMin = value
    case .xMax:      next.xMax = value
    case .leftYMin:  next.leftYMin = value
    case .leftYMax:  next.leftYMax = value
    case .rightYMin: next.rightYMin = value
    case .rightYMax: next.rightYMax = value
    }

    guard isValidRangePair(min: next.xMin, max: next.xMax),
          isValidRangePair(min: next.leftYMin, max: next.leftYMax),
          isValidRangePair(min: next.rightYMin, max: next.rightYMax) else {
        return current
    }

    return next.isEmpty ? nil : next
}

private func isValidRangePair(min: Double?, max: Double?) -> Bool {
    guard let min, let max else { return true }
    return min.isFinite && max.isFinite && max > min
}

// MARK: - DualAxis display state

/// Mutable display-state model edited by DualAxis controls.
/// Renderers consume `DualAxisDisplayStateSnapshot`, not this live state object.
struct DualAxisDisplayState: Codable, Hashable, Sendable {
    var titleOverride: String
    var xLabelOverride: String
    var leftYLabelOverride: String
    var rightYLabelOverride: String
    var axisRangeOverride: DualAxisAxisRangeOverride?
    var leftSeriesStyle: DualAxisSeriesVisualStyle
    var rightSeriesStyle: DualAxisSeriesVisualStyle
    var axisColorPolicy: DualAxisAxisColorPolicy

    init(
        titleOverride: String = "",
        xLabelOverride: String = "",
        leftYLabelOverride: String = "",
        rightYLabelOverride: String = "",
        axisRangeOverride: DualAxisAxisRangeOverride? = nil,
        leftSeriesStyle: DualAxisSeriesVisualStyle = .leftTemplate,
        rightSeriesStyle: DualAxisSeriesVisualStyle = .rightTemplate,
        axisColorPolicy: DualAxisAxisColorPolicy = .templatePaired
    ) {
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.leftYLabelOverride = leftYLabelOverride
        self.rightYLabelOverride = rightYLabelOverride
        self.axisRangeOverride = axisRangeOverride
        self.leftSeriesStyle = leftSeriesStyle
        self.rightSeriesStyle = rightSeriesStyle
        self.axisColorPolicy = axisColorPolicy
    }

    func snapshot() -> DualAxisDisplayStateSnapshot {
        DualAxisDisplayStateSnapshot(
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            leftYLabelOverride: leftYLabelOverride,
            rightYLabelOverride: rightYLabelOverride,
            axisRangeOverride: axisRangeOverride,
            leftSeriesStyle: leftSeriesStyle,
            rightSeriesStyle: rightSeriesStyle,
            axisColorPolicy: axisColorPolicy
        )
    }
}

/// Immutable snapshot captured before render.
/// This is the only display-state object the DualAxis pipeline/renderer should read.
struct DualAxisDisplayStateSnapshot: Codable, Hashable, Sendable {
    var titleOverride: String
    var xLabelOverride: String
    var leftYLabelOverride: String
    var rightYLabelOverride: String
    var axisRangeOverride: DualAxisAxisRangeOverride?
    var leftSeriesStyle: DualAxisSeriesVisualStyle
    var rightSeriesStyle: DualAxisSeriesVisualStyle
    var axisColorPolicy: DualAxisAxisColorPolicy

    init(
        titleOverride: String = "",
        xLabelOverride: String = "",
        leftYLabelOverride: String = "",
        rightYLabelOverride: String = "",
        axisRangeOverride: DualAxisAxisRangeOverride? = nil,
        leftSeriesStyle: DualAxisSeriesVisualStyle = .leftTemplate,
        rightSeriesStyle: DualAxisSeriesVisualStyle = .rightTemplate,
        axisColorPolicy: DualAxisAxisColorPolicy = .templatePaired
    ) {
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.leftYLabelOverride = leftYLabelOverride
        self.rightYLabelOverride = rightYLabelOverride
        self.axisRangeOverride = axisRangeOverride
        self.leftSeriesStyle = leftSeriesStyle
        self.rightSeriesStyle = rightSeriesStyle
        self.axisColorPolicy = axisColorPolicy
    }

    static let `default` = DualAxisDisplayStateSnapshot()

    func applying(to payload: DualAxisPlotPayload) -> DualAxisPlotPayload {
        var patched = payload
        if !titleOverride.isEmpty { patched.title = titleOverride }
        if !xLabelOverride.isEmpty { patched.xLabel = xLabelOverride }
        if !leftYLabelOverride.isEmpty { patched.leftYLabel = leftYLabelOverride }
        if !rightYLabelOverride.isEmpty { patched.rightYLabel = rightYLabelOverride }
        return patched
    }
}
