import Foundation

enum AHEChannel: String, Codable, Hashable, Sendable, CaseIterable {
    case ch1
    case ch2
    case ch3

    /// Delegates to the shared PPMS bridge mapping (Phase 4a; was a byte-for-byte duplicate of
    /// `RTPPMSDatParser.bridgeIndex(forChannel:)`). Force-unwrap is safe: `AHEChannel`'s only
    /// cases are ch1/ch2/ch3, all recognized by the shared mapping.
    var bridgeIndex: Int {
        PPMSBridgeChannelMapping.bridgeIndex(forChannel: rawValue)!
    }
}

struct AHEPlotSelectionItem: Codable, Hashable, Sendable {
    var sampleKey: String
    var sourceFilePath: String
    var channel: AHEChannel
    var conditions: [String: String]
    var workflowID: String
    var sampleSubstrate: String
    var batchID: String
    /// The originating `WorkflowMeasurementSearchHit.id` (sidecarPath), carried through so the
    /// rendered series can be looked up directly from Selected-hits state without fuzzy matching.
    /// One hit fans out into one `AHEPlotSelectionItem` per channel; all of a hit's channel
    /// selections share this same hitID — the explicit 1-hit-to-many representation.
    var hitID: String

    init(
        sampleKey: String,
        sourceFilePath: String,
        channel: AHEChannel,
        conditions: [String: String] = [:],
        workflowID: String = "AHE",
        sampleSubstrate: String = "",
        batchID: String = "",
        hitID: String = ""
    ) {
        self.sampleKey = sampleKey
        self.sourceFilePath = sourceFilePath
        self.channel = channel
        self.conditions = conditions
        self.workflowID = workflowID
        self.sampleSubstrate = sampleSubstrate
        self.batchID = batchID
        self.hitID = hitID
    }
}

struct AHEIngestionResult: Codable, Hashable, Sendable {
    var defaultAxisMapping: WorkbenchAxisMapping
    var series: [WorkbenchPlotSeries]
    var sourceFiles: [String]?
    var warnings: [String]

    init(
        defaultAxisMapping: WorkbenchAxisMapping,
        series: [WorkbenchPlotSeries],
        sourceFiles: [String]?,
        warnings: [String]
    ) {
        self.defaultAxisMapping = defaultAxisMapping
        self.series = series
        self.sourceFiles = sourceFiles
        self.warnings = warnings
    }
}
