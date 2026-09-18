import Foundation

/// AFM-specific save projection carrying all metadata needed to persist an AFM heatmap to
/// Library. Used exclusively by `SaveAFMChartToLibraryUseCase`; mirrors `RSMSaveProjection`.
struct AFMSaveProjection: Sendable {
    var workflowID: String
    var title: String
    var activeChannelID: String
    var channelSemanticType: String?
    var xLabel: String
    var yLabel: String
    var zLabel: String
    var sourceFileIdentity: String?
    var semanticParams: [String: String]
}
