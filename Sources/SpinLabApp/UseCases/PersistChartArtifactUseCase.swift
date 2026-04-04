import Foundation

struct ChartArtifactPersistenceResult: Sendable {
    var chartIdentityKey: String
    var imagePath: String       // relative to library root
    var manifestPath: String    // relative to library root
    var isOverwrite: Bool
    var manifest: WorkbenchRunManifest
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

    /// Multi-sample entry point. When `sampleKeys` has more than one element the
    /// PNG and manifest are written to `_spinlab/multi-sample/charts/` and a
    /// reference is inserted into each sample's own `results_index.json`.
    func execute(
        sampleKeys: [String],
        payload: WorkbenchPlotPayload,
        imageData: Data,
        runID: String = UUID().uuidString,
        generatedAt: Date = Date(),
        appVersion: String = AppVersion.current
    ) throws -> ChartArtifactPersistenceResult {
        let identityKey = WorkbenchChartIdentity.makeIdentityKey(from: payload)
        let isMulti = sampleKeys.count > 1

        // Build a human-readable filename: "{sanitized title}_{timestamp}"
        let rawTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = rawTitle.isEmpty ? "chart" : rawTitle
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let ts = fmt.string(from: generatedAt)
        let fileName = "\(safeTitle)_\(ts)"

        let imageRelPath: String
        let manifestRelPath: String
        if isMulti {
            imageRelPath    = "_spinlab/multi-sample/charts/\(fileName).png"
            manifestRelPath = "_spinlab/multi-sample/charts/\(fileName).manifest.json"
        } else {
            let sk = sampleKeys.first ?? "unknown"
            imageRelPath    = "samples/\(sk)/charts/\(fileName).png"
            manifestRelPath = "samples/\(sk)/charts/\(fileName).manifest.json"
        }

        let imageAbsURL    = try pathResolver.absoluteURL(for: imageRelPath)
        let manifestAbsURL = try pathResolver.absoluteURL(for: manifestRelPath)
        let isOverwrite    = FileManager.default.fileExists(atPath: imageAbsURL.path)

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

        // Build the shared reference object (same for all samples)
        let reference = WorkbenchResultReference(
            chartIdentityKey: identityKey,
            chartImagePath: imageRelPath,
            manifestPath: manifestRelPath,
            workflowID: payload.workflowID,
            generatedAt: generatedAt
        )

        // Upsert reference into each sample's results_index.json
        var indexEntries: [(URL, Data)] = []
        let uniqueKeys: [String] = {
            var seen = Set<String>()
            let deduped = sampleKeys.filter { seen.insert($0).inserted }
            return deduped.isEmpty ? ["unknown"] : deduped
        }()
        for sk in uniqueKeys {
            let indexRelPath = "samples/\(sk)/_spinlab/results_index.json"
            let indexAbsURL  = try pathResolver.absoluteURL(for: indexRelPath)
            var index: WorkbenchResultsIndex
            if let existing = try? Data(contentsOf: indexAbsURL),
               let decoded  = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: existing) {
                index = decoded
            } else {
                index = WorkbenchResultsIndex(sampleKey: sk, updatedAt: generatedAt, references: [])
            }
            if let existingIdx = index.references.firstIndex(where: { $0.chartIdentityKey == identityKey }) {
                index.references[existingIdx] = reference
            } else {
                index.references.append(reference)
            }
            index.updatedAt = generatedAt
            indexEntries.append((indexAbsURL, try Self.encoder.encode(index)))
        }

        let manifestData = try Self.encoder.encode(manifest)

        var writes: [AtomicWriteEntry] = [
            AtomicWriteEntry(destinationURL: imageAbsURL,    data: imageData),
            AtomicWriteEntry(destinationURL: manifestAbsURL, data: manifestData),
        ]
        for (url, data) in indexEntries {
            writes.append(AtomicWriteEntry(destinationURL: url, data: data))
        }
        try writer.commit(writes)

        return ChartArtifactPersistenceResult(
            chartIdentityKey: identityKey,
            imagePath: imageRelPath,
            manifestPath: manifestRelPath,
            isOverwrite: isOverwrite,
            manifest: manifest
        )
    }

    /// Convenience wrapper for single-sample callers.
    func execute(
        sampleKey: String,
        payload: WorkbenchPlotPayload,
        imageData: Data,
        runID: String = UUID().uuidString,
        generatedAt: Date = Date(),
        appVersion: String = AppVersion.current
    ) throws -> ChartArtifactPersistenceResult {
        try execute(
            sampleKeys: [sampleKey],
            payload: payload,
            imageData: imageData,
            runID: runID,
            generatedAt: generatedAt,
            appVersion: appVersion
        )
    }
}
