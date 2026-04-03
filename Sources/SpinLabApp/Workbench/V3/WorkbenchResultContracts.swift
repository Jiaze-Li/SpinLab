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

    init(label: String, x: [Double], y: [Double], sourceRef: String? = nil) {
        self.label = label
        self.x = x
        self.y = y
        self.sourceRef = sourceRef
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

struct WorkbenchMetricOverrideInfo: Codable, Hashable, Sendable {
    var oldValue: Double
    var newValue: Double
    var reason: String
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
