import Foundation

// MARK: - SaveRSMChartInput

struct SaveRSMChartInput: Sendable {
    var png: Data
    var projection: RSMSaveProjection
    var sampleKeys: [String]
    var libraryRootPath: String
    var runID: String
    var generatedAt: Date

    init(
        png: Data,
        projection: RSMSaveProjection,
        sampleKeys: [String],
        libraryRootPath: String,
        runID: String = UUID().uuidString,
        generatedAt: Date = Date()
    ) {
        self.png = png
        self.projection = projection
        self.sampleKeys = sampleKeys
        self.libraryRootPath = libraryRootPath
        self.runID = runID
        self.generatedAt = generatedAt
    }
}

// MARK: - SaveRSMChartToLibraryUseCase

/// RSM-specific save-to-Library use case.
///
/// Mirrors SaveActiveChartToLibraryUseCase but takes RSMSaveProjection instead of
/// WorkbenchPlotPayload. The existing Save Module (SaveActiveChartToLibraryUseCase +
/// PersistChartArtifactUseCase) is not modified and does not infer RSM semantics.
struct SaveRSMChartToLibraryUseCase {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    func execute(input: SaveRSMChartInput) -> PersistenceOutcome {
        guard !input.libraryRootPath.isEmpty else {
            return .failure("Library root path not set")
        }
        guard !input.sampleKeys.isEmpty else {
            return .failure("No sample keys provided")
        }

        let proj = input.projection
        let inputFiles: [String] = proj.sourceFileIdentity.map { [$0] } ?? []
        let axisMapping = WorkbenchAxisMapping(xField: proj.xLabel, yField: proj.yLabel)

        let identityKey = WorkbenchChartIdentity.makeIdentityKey(
            workflowID: proj.workflowID,
            inputFiles: inputFiles,
            axisMapping: axisMapping,
            semanticParams: proj.semanticParams
        )

        let resolver = LibraryPathResolver(libraryRootURL: URL(filePath: input.libraryRootPath))
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let writer = AtomicFileWriter()

        // Build filename from title + timestamp + identity hex suffix
        let rawTitle = proj.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = rawTitle.isEmpty ? "rsm" : rawTitle
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let ts = fmt.string(from: input.generatedAt)
        let hexSuffix = String(identityKey.dropFirst(6).prefix(16))
        let fileName = "\(safeTitle)_\(ts)_\(hexSuffix)"

        let imageRelPath = layout.chartImageRelativePath(fileName: fileName, sampleKeys: input.sampleKeys)
        let manifestRelPath = layout.chartManifestRelativePath(fileName: fileName, sampleKeys: input.sampleKeys)

        do {
            let imageAbsURL    = try resolver.absoluteURL(for: imageRelPath)
            let manifestAbsURL = try resolver.absoluteURL(for: manifestRelPath)

            let manifest = WorkbenchRunManifest(
                manifestID: UUID().uuidString,
                runID: input.runID,
                workflowID: proj.workflowID,
                inputFiles: inputFiles,
                filters: [:],
                axisMapping: axisMapping,
                semanticParams: proj.semanticParams,
                outputImagePath: imageRelPath,
                generatedAt: input.generatedAt,
                appVersion: AppVersion.current
            )

            let reference = WorkbenchResultReference(
                chartIdentityKey: identityKey,
                chartImagePath: imageRelPath,
                manifestPath: manifestRelPath,
                workflowID: proj.workflowID,
                generatedAt: input.generatedAt,
                tabKey: nil
            )

            let uniqueKeys: [String] = {
                var seen = Set<String>()
                let deduped = input.sampleKeys.filter { seen.insert($0).inserted }
                return deduped.isEmpty ? ["unknown"] : deduped
            }()

            var indexEntries: [(URL, Data)] = []
            var staleRelPaths = Set<String>()

            for sk in uniqueKeys {
                let indexAbsURL = try layout.resultsIndexURL(sampleKey: sk)
                let loadedIndex = indexStore.loadResultsIndexForMutation(sampleKey: sk, generatedAt: input.generatedAt)
                let mutation = indexStore.upsertChartReference(into: loadedIndex, reference: reference, updatedAt: input.generatedAt)
                if let previous = mutation.previousReference, previous.chartImagePath != imageRelPath {
                    staleRelPaths.insert(previous.chartImagePath)
                    staleRelPaths.insert(previous.manifestPath)
                }
                indexEntries.append((indexAbsURL, try indexStore.encodeResultsIndex(mutation.index)))

                let plotIndexAbsURL = try layout.measurementPlotIndexURL(sampleKey: sk)
                var plotIndex = indexStore.loadPlotIndexForMutation(sampleKey: sk, generatedAt: input.generatedAt)
                for inputFile in manifest.inputFiles {
                    plotIndex.upsert(chartIdentityKey: identityKey, sourceFile: inputFile)
                }
                plotIndex.updatedAt = input.generatedAt
                indexEntries.append((plotIndexAbsURL, try indexStore.encodePlotIndex(plotIndex)))
            }

            let manifestData = try Self.encoder.encode(manifest)

            var writes: [AtomicWriteEntry] = [
                AtomicWriteEntry(destinationURL: imageAbsURL,    data: input.png),
                AtomicWriteEntry(destinationURL: manifestAbsURL, data: manifestData),
            ]
            for (url, data) in indexEntries {
                writes.append(AtomicWriteEntry(destinationURL: url, data: data))
            }
            try writer.commit(writes)

            for stalePath in staleRelPaths {
                if let staleURL = try? resolver.absoluteURL(for: stalePath) {
                    try? FileManager.default.removeItem(at: staleURL)
                }
            }

            let trace = BuildRunTraceProjectionUseCase().execute(
                manifest: manifest,
                manifestPath: manifestRelPath
            )
            return .success(trace: trace)

        } catch {
            return .failure(AppError.from(error, fallback: "RSM chart persist failed").localizedDescription)
        }
    }
}
