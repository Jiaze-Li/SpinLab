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

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
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

        let isMulti = input.sampleKeys.count > 1
        let imageRelPath: String
        let manifestRelPath: String
        if isMulti {
            imageRelPath    = "_spinlab/multi-sample/charts/\(fileName).png"
            manifestRelPath = "_spinlab/multi-sample/charts/\(fileName).manifest.json"
        } else {
            let sk = input.sampleKeys.first ?? "unknown"
            imageRelPath    = "samples/\(sk)/charts/\(fileName).png"
            manifestRelPath = "samples/\(sk)/charts/\(fileName).manifest.json"
        }

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
                let indexRelPath = "samples/\(sk)/_spinlab/results_index.json"
                let indexAbsURL  = try resolver.absoluteURL(for: indexRelPath)
                var index: WorkbenchResultsIndex
                do {
                    let existing = try Data(contentsOf: indexAbsURL)
                    index = try Self.decoder.decode(WorkbenchResultsIndex.self, from: existing)
                } catch let nsErr as NSError
                    where nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
                    index = WorkbenchResultsIndex(sampleKey: sk, updatedAt: input.generatedAt, references: [])
                } catch {
                    fputs("[SpinLab] [SaveRSMChart] results_index corrupt, rebuilding (\(sk)): \(error)\n", stderr)
                    index = WorkbenchResultsIndex(sampleKey: sk, updatedAt: input.generatedAt, references: [])
                }

                if let existingIdx = index.references.firstIndex(where: { $0.chartIdentityKey == identityKey }) {
                    let old = index.references[existingIdx]
                    if old.chartImagePath != imageRelPath {
                        staleRelPaths.insert(old.chartImagePath)
                        staleRelPaths.insert(old.manifestPath)
                    }
                    index.references[existingIdx] = reference
                } else {
                    index.references.append(reference)
                }
                index.updatedAt = input.generatedAt
                indexEntries.append((indexAbsURL, try Self.encoder.encode(index)))

                let plotIndexRelPath = "samples/\(sk)/_spinlab/measurement_plot_index.json"
                let plotIndexAbsURL  = try resolver.absoluteURL(for: plotIndexRelPath)
                var plotIndex: MeasurementPlotIndex
                do {
                    let data = try Data(contentsOf: plotIndexAbsURL)
                    if let decoded = try? Self.decoder.decode(MeasurementPlotIndex.self, from: data) {
                        plotIndex = decoded
                    } else {
                        plotIndex = MeasurementPlotIndex(sampleKey: sk, updatedAt: input.generatedAt)
                    }
                } catch {
                    let nsErr = error as NSError
                    if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
                        plotIndex = MeasurementPlotIndex(sampleKey: sk, updatedAt: input.generatedAt)
                    } else {
                        throw error
                    }
                }
                for inputFile in manifest.inputFiles {
                    plotIndex.upsert(chartIdentityKey: identityKey, sourceFile: inputFile)
                }
                plotIndex.updatedAt = input.generatedAt
                indexEntries.append((plotIndexAbsURL, try Self.encoder.encode(plotIndex)))
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
