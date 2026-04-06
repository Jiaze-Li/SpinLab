import Foundation

struct WorkbenchAxisMapping: Codable, Hashable, Sendable {
    var xField: String
    var yField: String
}

struct WorkbenchPlotSeries: Codable, Hashable, Sendable {
    var label: String
    var x: [Double]
    var y: [Double]
    var sourceRef: String?
    var isScatter: Bool
    var pointLabels: [String]   // per-point annotation text for scatter series (empty = none)
    var lineWidth: Double        // line width for line series; default 1.5

    init(
        label: String,
        x: [Double],
        y: [Double],
        sourceRef: String? = nil,
        isScatter: Bool = false,
        pointLabels: [String] = [],
        lineWidth: Double = 1.5
    ) {
        self.label = label
        self.x = x
        self.y = y
        self.sourceRef = sourceRef
        self.isScatter = isScatter
        self.pointLabels = pointLabels
        self.lineWidth = lineWidth
    }
}

struct WorkbenchPlotPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workflowID: String
    var workflowDisplayName: String
    var title: String
    var axisMapping: WorkbenchAxisMapping
    var series: [WorkbenchPlotSeries]
    var semanticParams: [String: String]
    var styleParams: [String: String]

    init(
        schemaVersion: Int = 1,
        workflowID: String,
        workflowDisplayName: String,
        title: String,
        axisMapping: WorkbenchAxisMapping,
        series: [WorkbenchPlotSeries],
        semanticParams: [String: String] = [:],
        styleParams: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.workflowID = workflowID
        self.workflowDisplayName = workflowDisplayName
        self.title = title
        self.axisMapping = axisMapping
        self.series = series
        self.semanticParams = semanticParams
        self.styleParams = styleParams
    }
}

/// Identifies how a metric value override was produced (Adj-7).
/// Stored in `WorkbenchMetricOverrideInfo.source` for audit and future UI drill-down.
enum OverrideSource: String, Codable, Hashable, Sendable {
    /// User manually entered a corrected value before persisting.
    case manual
    /// Value was supplied by an import/batch pipeline rather than live computation.
    case `import`
    /// Value was updated by a re-computation pass (e.g. algorithm update).
    case recompute
}

struct WorkbenchMetricOverrideInfo: Codable, Hashable, Sendable {
    var oldValue: Double
    var newValue: Double
    var reason: String
    /// How this override was produced (Adj-7).
    var source: OverrideSource
    var at: Date
}

struct WorkbenchMetricRecord: Codable, Hashable, Identifiable, Sendable {
    var recordID: String
    var sampleKey: String
    var displayKey: String
    var workflowID: String
    var metric: String
    var value: Double
    var canonicalUnit: String
    var displayUnitHint: String?
    var conditions: [String: String]
    var generatedAt: Date
    var runID: String
    var overrideInfo: WorkbenchMetricOverrideInfo?

    var id: String { recordID }

    init(
        recordID: String,
        sampleKey: String,
        displayKey: String,
        workflowID: String,
        metric: String,
        value: Double,
        canonicalUnit: String,
        displayUnitHint: String? = nil,
        conditions: [String: String] = [:],
        generatedAt: Date,
        runID: String,
        overrideInfo: WorkbenchMetricOverrideInfo? = nil
    ) {
        self.recordID = recordID
        self.sampleKey = sampleKey
        self.displayKey = displayKey
        self.workflowID = workflowID
        self.metric = metric
        self.value = value
        self.canonicalUnit = canonicalUnit
        self.displayUnitHint = displayUnitHint
        self.conditions = conditions
        self.generatedAt = generatedAt
        self.runID = runID
        self.overrideInfo = overrideInfo
    }
}

struct WorkbenchRunManifest: Codable, Hashable, Identifiable, Sendable {
    var schemaVersion: Int
    var manifestID: String
    var runID: String
    var workflowID: String
    var inputFiles: [String]
    var filters: [String: String]
    var axisMapping: WorkbenchAxisMapping
    var semanticParams: [String: String]
    var outputImagePath: String
    var generatedAt: Date
    var appVersion: String

    var id: String { manifestID }

    init(
        schemaVersion: Int = 1,
        manifestID: String,
        runID: String,
        workflowID: String,
        inputFiles: [String],
        filters: [String: String],
        axisMapping: WorkbenchAxisMapping,
        semanticParams: [String: String],
        outputImagePath: String,
        generatedAt: Date,
        appVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.manifestID = manifestID
        self.runID = runID
        self.workflowID = workflowID
        self.inputFiles = inputFiles
        self.filters = filters
        self.axisMapping = axisMapping
        self.semanticParams = semanticParams
        self.outputImagePath = outputImagePath
        self.generatedAt = generatedAt
        self.appVersion = appVersion
    }
}

struct WorkbenchResultReference: Codable, Hashable, Sendable {
    var chartIdentityKey: String
    var chartImagePath: String
    var manifestPath: String
    var workflowID: String
    var generatedAt: Date
}

struct WorkbenchResultsIndex: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var sampleKey: String
    var updatedAt: Date
    var references: [WorkbenchResultReference]

    init(schemaVersion: Int = 1, sampleKey: String, updatedAt: Date, references: [WorkbenchResultReference]) {
        self.schemaVersion = schemaVersion
        self.sampleKey = sampleKey
        self.updatedAt = updatedAt
        self.references = references
    }
}

struct WorkbenchLatestMetricPointer: Codable, Hashable, Sendable {
    var recordID: String
    var value: Double
    var canonicalUnit: String
    var generatedAt: Date
}

struct WorkbenchMeasurementDataStore: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var records: [WorkbenchMetricRecord]
    var latestIndex: [String: WorkbenchLatestMetricPointer]

    init(
        schemaVersion: Int = 1,
        records: [WorkbenchMetricRecord] = [],
        latestIndex: [String: WorkbenchLatestMetricPointer] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
        self.latestIndex = latestIndex
    }

    mutating func append(_ record: WorkbenchMetricRecord) {
        records.append(record)
        let identity = WorkbenchMetricIdentity.makeIdentityKey(
            sampleKey: record.sampleKey,
            workflowID: record.workflowID,
            metric: record.metric,
            conditions: record.conditions
        )
        latestIndex[identity] = WorkbenchLatestMetricPointer(
            recordID: record.recordID,
            value: record.value,
            canonicalUnit: record.canonicalUnit,
            generatedAt: record.generatedAt
        )
    }
}
