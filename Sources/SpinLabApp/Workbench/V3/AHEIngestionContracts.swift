import Foundation

enum AHEChannel: String, Codable, Hashable, Sendable, CaseIterable {
    case ch1
    case ch2
    case ch3

    var bridgeIndex: Int {
        switch self {
        case .ch1: return 1
        case .ch2: return 2
        case .ch3: return 3
        }
    }
}

struct AHEPlotSelectionItem: Codable, Hashable, Sendable {
    var sampleKey: String
    var sourceFilePath: String
    var channel: AHEChannel
    var conditions: [String: String]
    var workflowID: String
    var sampleSubstrate: String

    init(
        sampleKey: String,
        sourceFilePath: String,
        channel: AHEChannel,
        conditions: [String: String] = [:],
        workflowID: String = "AHE",
        sampleSubstrate: String = ""
    ) {
        self.sampleKey = sampleKey
        self.sourceFilePath = sourceFilePath
        self.channel = channel
        self.conditions = conditions
        self.workflowID = workflowID
        self.sampleSubstrate = sampleSubstrate
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
