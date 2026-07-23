import Foundation

// MARK: - SaveActiveChartToLibraryUseCase
//
// Generic, workflow-agnostic UseCase for persisting a single chart image
// (the "active chart") plus optional metric records to the Library.
//
// Delegates to PersistChartArtifactUseCase (chart + link) and
// PersistMeasurementDataUseCase (metrics). Performs input validation
// and conditions normalization so callers don't have to.

struct PendingMetricEntry: Sendable {
    var sampleKey: String
    var metric: String
    var value: Double
    var canonicalUnit: String
    var conditions: [String: String]
    var overrideInfo: WorkbenchMetricOverrideInfo?
}

struct SaveActiveChartInput: Sendable {
    var png: Data
    var payload: WorkbenchPlotPayload
    var sampleKeys: [String]
    var libraryRootPath: String
    var metrics: [PendingMetricEntry]
    var runID: String
    var generatedAt: Date

    init(
        png: Data,
        payload: WorkbenchPlotPayload,
        sampleKeys: [String],
        libraryRootPath: String,
        metrics: [PendingMetricEntry] = [],
        runID: String = UUID().uuidString,
        generatedAt: Date = Date()
    ) {
        self.png = png
        self.payload = payload
        self.sampleKeys = sampleKeys
        self.libraryRootPath = libraryRootPath
        self.metrics = metrics
        self.runID = runID
        self.generatedAt = generatedAt
    }
}

struct SaveActiveChartToLibraryUseCase {

    func execute(input: SaveActiveChartInput) -> PersistenceOutcome {
        // --- Validation ---
        guard !input.libraryRootPath.isEmpty else {
            return .failure("Library root path not set")
        }
        guard !input.sampleKeys.isEmpty else {
            return .failure("No sample keys provided")
        }

        // metrics sampleKeys must be subset of input.sampleKeys
        let validKeys = Set(input.sampleKeys)
        let invalidMetricKeys = input.metrics.filter { !validKeys.contains($0.sampleKey) }
        if !invalidMetricKeys.isEmpty {
            let keys = invalidMetricKeys.map(\.sampleKey)
            return .failure("Metric sampleKey(s) \(keys) not in sampleKeys \(input.sampleKeys)")
        }

        // --- Persist chart ---
        let resolver = LibraryPathResolver(libraryRootURL: URL(filePath: input.libraryRootPath))
        let writer = AtomicFileWriter()

        let chartResult: ChartArtifactPersistenceResult
        do {
            chartResult = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
                .execute(
                    sampleKeys: input.sampleKeys,
                    payload: input.payload,
                    imageData: input.png,
                    runID: input.runID,
                    generatedAt: input.generatedAt
                )
        } catch {
            return .failure(AppError.from(error, fallback: "Chart persist failed").localizedDescription)
        }

        let trace = BuildRunTraceProjectionUseCase().execute(
            manifest: chartResult.manifest,
            manifestPath: chartResult.manifestPath
        )

        // --- Persist metrics (if any) ---
        guard !input.metrics.isEmpty else {
            return .success(trace: trace)
        }

        let metricUseCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
        for entry in input.metrics {
            // Normalize condition keys (lowercase + trim)
            let normalizedConditions = entry.conditions.reduce(into: [String: String]()) { result, pair in
                let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                result[key] = pair.value
            }

            let record = WorkbenchMetricRecord(
                recordID: UUID().uuidString,
                sampleKey: entry.sampleKey,
                displayKey: entry.sampleKey,
                workflowID: input.payload.workflowID,
                metric: entry.metric,
                value: entry.value,
                canonicalUnit: entry.canonicalUnit,
                conditions: normalizedConditions,
                generatedAt: input.generatedAt,
                runID: input.runID,
                overrideInfo: entry.overrideInfo
            )
            do {
                try metricUseCase.execute(sampleKey: entry.sampleKey, record: record)
            } catch {
                return .partial(
                    trace: trace,
                    metricError: AppError.from(error, fallback: "Metric '\(entry.metric)' persist failed for \(entry.sampleKey)").localizedDescription
                )
            }
        }

        return .success(trace: trace)
    }
}
