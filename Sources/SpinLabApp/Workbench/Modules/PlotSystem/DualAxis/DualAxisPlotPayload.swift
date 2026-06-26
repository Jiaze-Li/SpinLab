import Foundation

/// One data series for a dual-axis chart (Plot System contract).
/// Belongs to either the left or right axis; the axis assignment lives in DualAxisPlotPayload.
struct DualAxisPlotSeries: Codable, Hashable, Sendable {
    var label: String
    var x: [Double]
    var y: [Double]
    var renderMode: SeriesRenderMode
    var pointLabels: [String]
    var lineWidth: Double

    init(
        label: String,
        x: [Double],
        y: [Double],
        renderMode: SeriesRenderMode = .lineAndScatter,
        pointLabels: [String] = [],
        lineWidth: Double = 2.0
    ) {
        self.label = label
        self.x = x
        self.y = y
        self.renderMode = renderMode
        self.pointLabels = pointLabels
        self.lineWidth = lineWidth
    }
}

/// Plot System input contract for the dual-axis render path.
/// Parallel to WorkbenchPlotPayload; carries independent left and right Y-axis series.
/// Must not inherit or extend WorkbenchPlotPayload.
struct DualAxisPlotPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workflowID: String
    var workflowDisplayName: String
    var title: String
    var xLabel: String
    var leftYLabel: String
    var rightYLabel: String
    var leftSeries: [DualAxisPlotSeries]
    var rightSeries: [DualAxisPlotSeries]
    /// Workflow-specific key–value annotations. Must not carry 3ω / RAHE / domain semantics.
    var semanticParams: [String: String]
    /// Rendering hint overrides (e.g. colors, point sizes).
    var styleParams: [String: String]

    init(
        schemaVersion: Int = 1,
        workflowID: String,
        workflowDisplayName: String,
        title: String,
        xLabel: String,
        leftYLabel: String,
        rightYLabel: String,
        leftSeries: [DualAxisPlotSeries] = [],
        rightSeries: [DualAxisPlotSeries] = [],
        semanticParams: [String: String] = [:],
        styleParams: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.workflowID = workflowID
        self.workflowDisplayName = workflowDisplayName
        self.title = title
        self.xLabel = xLabel
        self.leftYLabel = leftYLabel
        self.rightYLabel = rightYLabel
        self.leftSeries = leftSeries
        self.rightSeries = rightSeries
        self.semanticParams = semanticParams
        self.styleParams = styleParams
    }
}
