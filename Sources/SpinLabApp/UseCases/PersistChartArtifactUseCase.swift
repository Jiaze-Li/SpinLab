import Foundation

struct ChartArtifactPersistenceResult: Sendable {
    var chartIdentityKey: String
    var imagePath: String       // relative to library root
    var manifestPath: String    // relative to library root
    var isOverwrite: Bool
}

struct PersistChartArtifactUseCase {
    let writer: AtomicFileWritingCapability
    let pathResolver: LibraryPathResolver

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func execute(
        sampleKey: String,
        payload: WorkbenchPlotPayload,
        imageData: Data,
        runID: String = UUID().uuidString,
        generatedAt: Date = Date(),
        appVersion: String = "v3.2.4"
    ) throws -> ChartArtifactPersistenceResult {
        let identityKey = WorkbenchChartIdentity.makeIdentityKey(from: payload)

        let imageRelPath = "samples/\(sampleKey)/charts/\(identityKey).png"
        let manifestRelPath = "samples/\(sampleKey)/charts/\(identityKey).manifest.json"
        let indexRelPath = "samples/\(sampleKey)/_spinlab/results_index.json"

        let imageAbsURL = try pathResolver.absoluteURL(for: imageRelPath)
        let manifestAbsURL = try pathResolver.absoluteURL(for: manifestRelPath)
        let indexAbsURL = try pathResolver.absoluteURL(for: indexRelPath)

        let isOverwrite = FileManager.default.fileExists(atPath: imageAbsURL.path)

        // Build manifest
        let inputFiles = payload.series.compactMap(\.sourceRef)
        let manifest = WorkbenchRunManifest(
            manifestID: UUID().uuidString,
            runID: runID,
            workflowID: payload.workflowID,
            inputFiles: inputFiles,
            filters: [:],
            axisMapping: payload.axisMapping,
            semanticParams: payload.semanticParams,
            outputImagePath: imageRelPath,
            generatedAt: generatedAt,
            appVersion: appVersion
        )

        // Load existing index or create fresh one
        var index: WorkbenchResultsIndex
        if let existing = try? Data(contentsOf: indexAbsURL),
           let decoded = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: existing) {
            index = decoded
        } else {
            index = WorkbenchResultsIndex(sampleKey: sampleKey, updatedAt: generatedAt, references: [])
        }

        // Upsert reference by chartIdentityKey
        let reference = WorkbenchResultReference(
            chartIdentityKey: identityKey,
            chartImagePath: imageRelPath,
            manifestPath: manifestRelPath,
            workflowID: payload.workflowID,
            generatedAt: generatedAt
        )
        if let existingIdx = index.references.firstIndex(where: { $0.chartIdentityKey == identityKey }) {
            index.references[existingIdx] = reference
        } else {
            index.references.append(reference)
        }
        index.updatedAt = generatedAt

        let manifestData = try Self.encoder.encode(manifest)
        let indexData = try Self.encoder.encode(index)

        try writer.commit([
            AtomicWriteEntry(destinationURL: imageAbsURL, data: imageData),
            AtomicWriteEntry(destinationURL: manifestAbsURL, data: manifestData),
            AtomicWriteEntry(destinationURL: indexAbsURL, data: indexData),
        ])

        return ChartArtifactPersistenceResult(
            chartIdentityKey: identityKey,
            imagePath: imageRelPath,
            manifestPath: manifestRelPath,
            isOverwrite: isOverwrite
        )
    }
}
