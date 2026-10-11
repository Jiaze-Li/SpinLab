import Foundation

/// 2D grid data for a heatmap render path (Plot System contract).
/// Must not inherit or extend WorkbenchPlotPayload/WorkbenchPlotSeries.
struct HeatmapGrid: Codable, Hashable, Sendable {
    /// nX axis values (column labels).
    var xValues: [Double]
    /// nY axis values (row labels).
    var yValues: [Double]
    /// Row-major Z matrix: zMatrix[row][col] where row=0 ↔ yValues[0], col=0 ↔ xValues[0].
    var zMatrix: [[Double]]

    var nX: Int { xValues.count }
    var nY: Int { yValues.count }

    /// True iff matrix dimensions are consistent with axis label counts.
    ///
    /// V1 validation policy:
    /// - Checks only that nX > 0, nY > 0, and zMatrix is nY × nX.
    /// - Does NOT reject NaN or Inf Z values. HeatmapColorScale clamps them:
    ///   NaN → minimum color (t=0); +Inf → maximum color (t=1); -Inf → minimum color (t=0).
    /// - Does NOT reject non-monotonic axis values. Cells are always drawn in
    ///   array row/column order. For the scientific convention (lower y value
    ///   appears lower on the plot) to hold, yValues must be strictly ascending.
    ///   Passing descending or non-monotonic yValues renders cells correctly by
    ///   array index but visual tick-label alignment will be inverted or arbitrary.
    var isValid: Bool {
        guard nX > 0, nY > 0 else { return false }
        return zMatrix.count == nY && zMatrix.allSatisfy { $0.count == nX }
    }

    /// Physical data aspect ratio (xSpan / ySpan) when coordinates are known and non-zero.
    var physicalDataAspectRatio: Double? {
        guard let minX = xValues.min(), let maxX = xValues.max(),
              let minY = yValues.min(), let maxY = yValues.max() else {
            return nil
        }
        let xSpan = maxX - minX
        let ySpan = maxY - minY
        guard xSpan > 0, ySpan > 0, xSpan.isFinite, ySpan.isFinite else {
            return nil
        }
        // The renderer draws nX × nY equal cells, so the drawn extent is one pixel pitch larger
        // than the center-to-center span on each axis.
        let xExtent = nX > 1 ? xSpan * Double(nX) / Double(nX - 1) : xSpan
        let yExtent = nY > 1 ? ySpan * Double(nY) / Double(nY - 1) : ySpan
        return xExtent / yExtent
    }
}

/// Aspect ratio policy for heatmap grid rendering.
enum HeatmapAspectPolicy: String, Codable, Hashable, Sendable {
    /// Grid stretches to fill the available canvas area (default; used by RSM).
    case fill
    /// Grid preserves physical data-unit coordinates aspect ratio (xSpan / ySpan).
    case physical
}

/// Scale bar colour choice; the outline always uses the opposite, high-contrast colour.
enum HeatmapScaleBarColor: String, Codable, Hashable, Sendable, CaseIterable {
    case white
    case black
}

/// Visual scale bar overlay configuration for spatial heatmap display.
/// Workflow-agnostic display contract (Plot System-owned).
struct HeatmapScaleBarOverlay: Codable, Hashable, Sendable {
    /// Physical width of the scale bar line in points.
    var lengthInPoints: CGFloat
    /// Formatted display label (e.g. "5 μm").
    var label: String
    /// Physical bar length in the X-axis data units. When set, layout derives `lengthInPoints`
    /// from the grid's real extent so the bar always matches the scan scale.
    var physicalLength: Double?
    /// Bar + label colour. Nil = white (the original behaviour).
    var color: HeatmapScaleBarColor?

    init(lengthInPoints: CGFloat, label: String, physicalLength: Double? = nil, color: HeatmapScaleBarColor? = nil) {
        self.lengthInPoints = lengthInPoints
        self.label = label
        self.physicalLength = physicalLength
        self.color = color
    }
}

/// Plot System input contract for the heatmap render path.
/// Parallel to WorkbenchPlotPayload; carries 2D grid data instead of XY series.
struct HeatmapPlotPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workflowID: String
    var title: String
    var xLabel: String
    var yLabel: String
    /// Colorbar title (Z-axis label).
    var zLabel: String
    var grid: HeatmapGrid
    /// Colormap hint key (e.g. "viridis"); nil = viridis default.
    var colormapKey: String?
    /// Optional Z-range clamp lower bound. Nil = auto from data.
    var zRangeClampMin: Double?
    /// Optional Z-range clamp upper bound. Nil = auto from data.
    var zRangeClampMax: Double?
    /// Aspect ratio policy for the plot grid. Defaults to .fill.
    var aspectPolicy: HeatmapAspectPolicy
    /// Optional scale bar overlay (drawn inside lower-left of grid).
    var scaleBarOverlay: HeatmapScaleBarOverlay?
    /// Whether spatial X/Y axes (ticks and labels) should be hidden.
    var hideSpatialAxes: Bool

    init(
        schemaVersion: Int = 1,
        workflowID: String,
        title: String,
        xLabel: String,
        yLabel: String,
        zLabel: String,
        grid: HeatmapGrid,
        colormapKey: String? = nil,
        zRangeClamp: ClosedRange<Double>? = nil,
        aspectPolicy: HeatmapAspectPolicy = .fill,
        scaleBarOverlay: HeatmapScaleBarOverlay? = nil,
        hideSpatialAxes: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.workflowID = workflowID
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.zLabel = zLabel
        self.grid = grid
        self.colormapKey = colormapKey
        self.zRangeClampMin = zRangeClamp?.lowerBound
        self.zRangeClampMax = zRangeClamp?.upperBound
        self.aspectPolicy = aspectPolicy
        self.scaleBarOverlay = scaleBarOverlay
        self.hideSpatialAxes = hideSpatialAxes
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, workflowID, title, xLabel, yLabel, zLabel
        case grid, colormapKey, zRangeClampMin, zRangeClampMax, aspectPolicy
        case scaleBarOverlay, hideSpatialAxes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        workflowID = try container.decode(String.self, forKey: .workflowID)
        title = try container.decode(String.self, forKey: .title)
        xLabel = try container.decode(String.self, forKey: .xLabel)
        yLabel = try container.decode(String.self, forKey: .yLabel)
        zLabel = try container.decode(String.self, forKey: .zLabel)
        grid = try container.decode(HeatmapGrid.self, forKey: .grid)
        colormapKey = try container.decodeIfPresent(String.self, forKey: .colormapKey)
        zRangeClampMin = try container.decodeIfPresent(Double.self, forKey: .zRangeClampMin)
        zRangeClampMax = try container.decodeIfPresent(Double.self, forKey: .zRangeClampMax)
        aspectPolicy = try container.decodeIfPresent(HeatmapAspectPolicy.self, forKey: .aspectPolicy) ?? .fill
        scaleBarOverlay = try container.decodeIfPresent(HeatmapScaleBarOverlay.self, forKey: .scaleBarOverlay)
        hideSpatialAxes = try container.decodeIfPresent(Bool.self, forKey: .hideSpatialAxes) ?? false
    }
}
