import Foundation

struct WorkbenchAxisMapping: Codable, Hashable, Sendable {
    var xField: String
    var yField: String
}

/// How a series is rendered on the chart.
enum SeriesRenderMode: String, Codable, Hashable, Sendable {
    case line
    case scatter
    case lineAndScatter
}

struct WorkbenchPlotSeries: Hashable, Sendable {
    var label: String
    var x: [Double]
    var y: [Double]
    var sourceRef: String?
    var renderMode: SeriesRenderMode
    var pointLabels: [String]   // per-point annotation text for scatter series (empty = none)
    var lineWidth: Double        // line width for line series; default 1.5

    /// Sample/condition metadata carried from search hit through ingestion to plotting (v5.3.4).
    /// Used by LegendDimensionResolver to auto-infer the distinguishing dimension.
    /// Keys follow resolver chain keys: "temperature", "substrate", "energy", "pressure", "thickness".
    var metadata: [String: String]

    init(
        label: String,
        x: [Double],
        y: [Double],
        sourceRef: String? = nil,
        renderMode: SeriesRenderMode = .line,
        pointLabels: [String] = [],
        lineWidth: Double = 2.0,
        metadata: [String: String] = [:]
    ) {
        self.label = label
        self.x = x
        self.y = y
        self.sourceRef = sourceRef
        self.renderMode = renderMode
        self.pointLabels = pointLabels
        self.lineWidth = lineWidth
        self.metadata = metadata
    }

    /// Convenience initializer preserving old `isScatter` call sites during migration.
    init(
        label: String,
        x: [Double],
        y: [Double],
        sourceRef: String? = nil,
        isScatter: Bool,
        pointLabels: [String] = [],
        lineWidth: Double = 2.0,
        metadata: [String: String] = [:]
    ) {
        self.init(
            label: label, x: x, y: y, sourceRef: sourceRef,
            renderMode: isScatter ? .scatter : .line,
            pointLabels: pointLabels, lineWidth: lineWidth,
            metadata: metadata
        )
    }
}

// MARK: - Codable migration (isScatter → renderMode)

extension WorkbenchPlotSeries: Codable {
    private enum CodingKeys: String, CodingKey {
        case label, x, y, sourceRef, renderMode, pointLabels, lineWidth, metadata
        case isScatter  // legacy key — read-only
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label       = try c.decode(String.self, forKey: .label)
        x           = try c.decode([Double].self, forKey: .x)
        y           = try c.decode([Double].self, forKey: .y)
        sourceRef   = try c.decodeIfPresent(String.self, forKey: .sourceRef)
        pointLabels = try c.decodeIfPresent([String].self, forKey: .pointLabels) ?? []
        lineWidth   = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 1.5
        metadata    = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        // Prefer renderMode; fall back to legacy isScatter
        if let mode = try? c.decode(SeriesRenderMode.self, forKey: .renderMode) {
            renderMode = mode
        } else if let scatter = try? c.decode(Bool.self, forKey: .isScatter) {
            renderMode = scatter ? .scatter : .line
        } else {
            renderMode = .line
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encodeIfPresent(sourceRef, forKey: .sourceRef)
        try c.encode(renderMode, forKey: .renderMode)
        try c.encode(pointLabels, forKey: .pointLabels)
        try c.encode(lineWidth, forKey: .lineWidth)
        if !metadata.isEmpty { try c.encode(metadata, forKey: .metadata) }
        // Do NOT encode isScatter — new format only
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

    /// The metadata dimension that distinguishes series in this chart (v5.3.4).
    /// e.g. "Temperature (K)", "Substrate", "Energy". nil = not resolved or single series.
    var legendDimension: String?

    /// Whether series should be reverse-sorted so that the highest stacked curve
    /// appears first in the legend (index 0 = legend top = visual top). Default true. (v5.3.4)
    var reverseSeriesForLegend: Bool

    init(
        schemaVersion: Int = 1,
        workflowID: String,
        workflowDisplayName: String,
        title: String,
        axisMapping: WorkbenchAxisMapping,
        series: [WorkbenchPlotSeries],
        semanticParams: [String: String] = [:],
        styleParams: [String: String] = [:],
        legendDimension: String? = nil,
        reverseSeriesForLegend: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.workflowID = workflowID
        self.workflowDisplayName = workflowDisplayName
        self.title = title
        self.axisMapping = axisMapping
        self.series = series
        self.semanticParams = semanticParams
        self.styleParams = styleParams
        self.legendDimension = legendDimension
        self.reverseSeriesForLegend = reverseSeriesForLegend
    }

    // Backward-compatible decode: legendDimension defaults nil, reverseSeriesForLegend defaults true.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion          = try c.decode(Int.self, forKey: .schemaVersion)
        workflowID             = try c.decode(String.self, forKey: .workflowID)
        workflowDisplayName    = try c.decode(String.self, forKey: .workflowDisplayName)
        title                  = try c.decode(String.self, forKey: .title)
        axisMapping            = try c.decode(WorkbenchAxisMapping.self, forKey: .axisMapping)
        series                 = try c.decode([WorkbenchPlotSeries].self, forKey: .series)
        semanticParams         = try c.decode([String: String].self, forKey: .semanticParams)
        styleParams            = try c.decode([String: String].self, forKey: .styleParams)
        legendDimension        = try c.decodeIfPresent(String.self, forKey: .legendDimension)
        reverseSeriesForLegend = try c.decodeIfPresent(Bool.self, forKey: .reverseSeriesForLegend) ?? true
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
    var tabKey: String?

    /// Returns stored `tabKey` if present, otherwise infers from `chartImagePath` filename prefix.
    var resolvedTabKey: String? {
        if let tabKey { return tabKey }
        let filename = URL(fileURLWithPath: chartImagePath).lastPathComponent
        if filename.hasPrefix("R1ω_") || filename.hasPrefix("R1\u{03C9}_")   { return "fieldSweep1omega" }
        if filename.hasPrefix("R3ω_") || filename.hasPrefix("R3\u{03C9}_")   { return "fieldSweep3omega" }
        if filename.hasPrefix("RAHE1ω") || filename.hasPrefix("RAHE1\u{03C9}") { return "rahe1omegaVsT" }
        if filename.hasPrefix("RAHE3ω") || filename.hasPrefix("RAHE3\u{03C9}") { return "rahe3omegaVsT" }
        if filename.hasPrefix("Hc_")             { return "hcVsT" }
        if filename.hasPrefix("Rxx_vs_T_") || filename.hasPrefix("RT_") { return "rtCurve" }
        if filename.hasPrefix("Scaling_Law_")    { return "scaling" }
        return nil
    }
}

extension WorkbenchResultReference {
    /// Canonical sort: tab rank (1ω → 3ω → RAHE → Hc → RT → Scaling), then generatedAt ascending.
    /// Shared by Library detail and Workbench related-charts popover.
    static func sortedByTabRank(_ refs: [WorkbenchResultReference]) -> [WorkbenchResultReference] {
        let rankMap = ThreeOmegaWorkbenchTab.stableKeyRank
        let fallbackRank = rankMap.count
        return refs.enumerated()
            .sorted { a, b in
                let rankA = a.element.resolvedTabKey.flatMap { rankMap[$0] } ?? fallbackRank
                let rankB = b.element.resolvedTabKey.flatMap { rankMap[$0] } ?? fallbackRank
                if rankA != rankB { return rankA < rankB }
                if a.element.generatedAt != b.element.generatedAt {
                    return a.element.generatedAt < b.element.generatedAt
                }
                return a.offset < b.offset
            }
            .map(\.element)
    }
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

// MARK: - MeasurementPlotIndex (v4.1.2.17)

/// Reverse index from source measurement filename to chart identity keys.
/// Stored at `samples/{sampleKey}/_spinlab/measurement_plot_index.json`.
/// Images are NOT duplicated — this struct holds only `chartIdentityKey` references
/// that point into `WorkbenchResultsIndex.references`.
struct MeasurementPlotIndex: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var sampleKey: String
    var updatedAt: Date
    /// Key: `URL(fileURLWithPath: sourceRef).lastPathComponent` (matches `AppliedMeasurement.sourceFileName`)
    /// Value: ordered list of `chartIdentityKey` strings
    var entries: [String: [String]]

    init(
        schemaVersion: Int = 1,
        sampleKey: String,
        updatedAt: Date,
        entries: [String: [String]] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.sampleKey = sampleKey
        self.updatedAt = updatedAt
        self.entries = entries
    }

    /// Adds `chartIdentityKey` under the normalized filename key for `sourceFile`.
    /// Idempotent: duplicate keys are not inserted.
    mutating func upsert(chartIdentityKey: String, sourceFile: String) {
        let key = URL(fileURLWithPath: sourceFile).lastPathComponent
        var ids = entries[key] ?? []
        if !ids.contains(chartIdentityKey) {
            ids.append(chartIdentityKey)
        }
        entries[key] = ids
    }
}

// MARK: - Canonical InputFiles Key

enum InputFilesCanonicalKey {
    /// Produces a stable, order-independent key from a list of input file paths.
    /// Used to group charts that share the exact same set of source files.
    static func make(from inputFiles: [String]) -> String {
        inputFiles.sorted().joined(separator: "\n")
    }
}

/// Per-series AHE metric extraction result, keyed by sampleKey for stable mapping.
struct AHEExtractedMetric: Equatable, Sendable {
    var sampleKey: String
    var hc: Double
    var rAHE: Double
}

/// Error produced when AHE metric extraction fails for one or more series.
enum AHEMetricExtractionError: Error, Equatable, Sendable {
    /// One or more series labels could not be parsed to extract a sampleKey.
    /// The associated value lists the unparseable labels for diagnostics.
    case unparseableLabels([String])
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
