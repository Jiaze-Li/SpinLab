import Foundation

enum LibrarySampleEmptyCheckResult: Equatable, Sendable {
    case empty
    case nonEmpty(reasons: [String])
    case unreadable(reason: String)

    var requiresConfirmation: Bool {
        switch self {
        case .empty:
            return false
        case .nonEmpty, .unreadable:
            return true
        }
    }
}

/// Fail-closed read-only check determining whether a sample is truly empty
/// (no manual parameters, no measurements, no charts, no drawer files, and no unreadable artifacts).
struct LibrarySampleEmptyCheck {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func evaluate(sample: LibrarySample, rootURL: URL, libraryStore: LibraryStore) -> LibrarySampleEmptyCheckResult {
        var reasons: [String] = []

        // 1. Sample metadata / manual parameters
        let hasMetadata = sample.metadata.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasOrderedMetadata = sample.orderedMetadata.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasMetadata || hasOrderedMetadata {
            reasons.append("Has manual metadata parameters")
        }
        if !sample.numericTags.isEmpty || !sample.numericDisplay.isEmpty {
            reasons.append("Has numeric parameters")
        }

        // 2. Applied measurements and measurement sets (in-memory)
        if !sample.appliedMeasurements.isEmpty {
            reasons.append("Has applied measurements")
        }
        if !sample.measurementSets.isEmpty {
            reasons.append("Has measurement sets")
        }

        // 3. Physical sample drawer directory: batches/<batch>/samples/<sampleKey>/
        let sampleDir = libraryStore.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let sampleJSONURL = sampleDir.appending(path: "sample.json")
        guard fileManager.fileExists(atPath: sampleJSONURL.path),
              libraryStore.decodeSample(from: sampleJSONURL) != nil else {
            return .unreadable(reason: "sample.json is missing or unreadable")
        }

        // Confirmed Result values on disk make the Sample non-empty (Definitions alone do not).
        if let diskSample = libraryStore.decodeSample(from: sampleJSONURL),
           diskSample.results?.isEmpty == false {
            reasons.append("Has Sample Result values")
        }

        let measurementSetsURL = sampleDir.appending(path: LibraryStore.measurementSetsFileName)
        if fileManager.fileExists(atPath: measurementSetsURL.path) {
            do {
                let data = try Data(contentsOf: measurementSetsURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let sets = try decoder.decode([MeasurementSet].self, from: data)
                if !sets.isEmpty {
                    reasons.append("Has saved measurement sets")
                }
            } catch {
                return .unreadable(reason: "measurement_sets.json is unreadable or corrupt")
            }
        }

        switch checkDrawerFiles(at: sampleDir) {
        case .ok(let hasFiles):
            if hasFiles {
                reasons.append("Has measurement or drawer files")
            }
        case .unreadable(let reason):
            return .unreadable(reason: reason)
        }

        // 4. Workbench artifact directory: samples/<sampleKey>/
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let chartIndexStore = LibraryChartIndexStore(layout: layout)
        let measurementDataStore = LibraryMeasurementDataStore(layout: layout)

        let candidateKeys = Array(Set([sample.id, libraryStore.sanitizedPathComponent(sample.id)]))
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }

        for key in candidateKeys {
            do {
                if let store = try measurementDataStore.loadStrict(sampleKey: key) {
                    if !store.records.isEmpty || !store.latestIndex.isEmpty {
                        reasons.append("Has Workbench measurement data")
                    }
                }
            } catch {
                return .unreadable(reason: "measurement_data.json is unreadable or corrupt")
            }

            switch chartIndexStore.loadResultsIndexForAudit(sampleKey: key) {
            case .missing:
                break
            case .corrupt:
                return .unreadable(reason: "results_index.json is unreadable or corrupt")
            case .ok(let index):
                if !index.references.isEmpty {
                    reasons.append("Has saved result charts")
                }
            }

            do {
                if let plotResult = try chartIndexStore.loadPlotIndexStrict(sampleKey: key),
                   !plotResult.index.entries.isEmpty {
                    reasons.append("Has measurement plot links")
                }
            } catch {
                return .unreadable(reason: "measurement_plot_index.json is unreadable or corrupt")
            }

            do {
                let chartsURL = try layout.pathResolver.absoluteURL(
                    for: layout.singleSampleChartDirectoryRelativePath(sampleKey: key)
                )
                switch checkChartsDirectory(at: chartsURL) {
                case .ok(let hasCharts):
                    if hasCharts {
                        reasons.append("Has chart files")
                    }
                case .unreadable(let reason):
                    return .unreadable(reason: reason)
                }
            } catch {
                return .unreadable(reason: "Invalid chart directory path")
            }
        }

        if reasons.isEmpty {
            return .empty
        }
        return .nonEmpty(reasons: deduplicated(reasons))
    }

    private enum DirectoryCheckResult {
        case ok(hasNonEmptyFiles: Bool)
        case unreadable(reason: String)
    }

    private func checkDrawerFiles(at sampleDir: URL) -> DirectoryCheckResult {
        guard fileManager.fileExists(atPath: sampleDir.path) else {
            return .unreadable(reason: "Sample directory is missing")
        }
        var didFail = false
        guard let enumerator = fileManager.enumerator(
            at: sampleDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in
                didFail = true
                return false
            }
        ) else {
            return .unreadable(reason: "Sample directory cannot be enumerated")
        }

        let ignoredNames: Set<String> = ["sample.json", LibraryStore.measurementSetsFileName]
        while let item = enumerator.nextObject() as? URL {
            let name = item.lastPathComponent
            if name.hasPrefix(".") {
                continue
            }
            let values: URLResourceValues
            do {
                values = try item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            } catch {
                return .unreadable(reason: "Sample drawer entry is unreadable: \(name)")
            }
            if values.isDirectory == true {
                continue
            }
            if values.isRegularFile == true && !ignoredNames.contains(name) {
                return .ok(hasNonEmptyFiles: true)
            }
        }
        if didFail {
            return .unreadable(reason: "Sample directory enumeration failed")
        }
        return .ok(hasNonEmptyFiles: false)
    }

    private func checkChartsDirectory(at chartsURL: URL) -> DirectoryCheckResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: chartsURL.path, isDirectory: &isDirectory) else {
            return .ok(hasNonEmptyFiles: false)
        }
        guard isDirectory.boolValue else {
            return .unreadable(reason: "Charts path is not a directory")
        }
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: chartsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
        } catch {
            return .unreadable(reason: "Charts directory cannot be read")
        }
        for url in contents {
            if url.lastPathComponent.hasPrefix(".") {
                continue
            }
            return .ok(hasNonEmptyFiles: true)
        }
        return .ok(hasNonEmptyFiles: false)
    }

    private func deduplicated(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
