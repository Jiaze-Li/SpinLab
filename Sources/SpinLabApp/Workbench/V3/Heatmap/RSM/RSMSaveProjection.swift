import Foundation

/// RSM-specific save projection carrying all metadata needed to persist an RSM heatmap to Library.
/// Used exclusively by SaveRSMChartToLibraryUseCase; never touches the Cartesian XY save path.
struct RSMSaveProjection: Sendable {
    var workflowID: String
    var title: String
    var activeView: RSMView
    var detectorColumnName: String
    var xLabel: String
    var yLabel: String
    var zLabel: String
    var sourceFileIdentity: String?
    var semanticParams: [String: String]
}
