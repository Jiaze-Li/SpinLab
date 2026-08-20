import Foundation

/// Explicit read status for audit-grade index loads. Unlike the fail-soft and
/// strict loaders, audit callers must be able to tell "nothing here" apart from
/// "something here we could not read" — collapsing both to nil/empty is the
/// exact bug this type exists to prevent (corrupt index → orphan misclassification).
enum LibraryIndexReadStatus<T> {
    case ok(T)
    case missing
    case corrupt
}

/// Storage-level result of upserting a chart reference into a `WorkbenchResultsIndex`.
///
/// Library owns HOW the mutation is applied (find-by-identity, replace-or-append,
/// bump `updatedAt`) and reports back the previous reference as a plain storage
/// fact. Library does **not** decide whether that previous reference makes this
/// an "overwrite", or whether its files are now "stale" — those are Workbench
/// save semantics and stay in the calling UseCase.
struct ChartIndexMutationResult {
    var index: WorkbenchResultsIndex
    var previousReference: WorkbenchResultReference?
}

/// Sole owner of `results_index.json` / `measurement_plot_index.json` codec,
/// canonical encoder/decoder configuration, and missing-vs-corrupt read policy.
///
/// Three distinct read semantics are preserved as three distinct method families,
/// on purpose — collapsing them behind a single Bool or Optional is exactly the
/// kind of policy-via-flag this type exists to avoid:
/// - mutation/save: missing → empty index, corrupt → rebuild empty + log
/// - destructive:    missing → nil,        corrupt → throw
/// - audit:          `.ok` / `.missing` / `.corrupt`
struct LibraryChartIndexStore {
    let layout: LibraryArtifactLayout

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Encoding

    func encodeResultsIndex(_ index: WorkbenchResultsIndex) throws -> Data {
        try Self.encoder.encode(index)
    }

    func encodePlotIndex(_ index: MeasurementPlotIndex) throws -> Data {
        try Self.encoder.encode(index)
    }

    // MARK: - Mutation-style loads (missing → empty, corrupt → rebuild empty + log)

    func loadResultsIndexForMutation(sampleKey: String, generatedAt: Date) -> WorkbenchResultsIndex {
        let empty = WorkbenchResultsIndex(sampleKey: sampleKey, updatedAt: generatedAt, references: [])
        guard let url = try? layout.resultsIndexURL(sampleKey: sampleKey) else { return empty }
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(WorkbenchResultsIndex.self, from: data)
        } catch let nsErr as NSError where nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
            return empty
        } catch {
            fputs("[SpinLab] LibraryChartIndexStore: results_index corrupt, rebuilding (\(sampleKey)): \(error)\n", stderr)
            return empty
        }
    }

    /// Missing file → empty index (nothing to preserve). JSON decode corruption →
    /// rebuild empty + log, matching this family's established save policy. A
    /// non-missing read error (permissions, transient filesystem fault, …) must
    /// NOT be treated as "nothing here" — doing so would let a save silently
    /// replace an existing, unreadable-right-now index with an empty one. Throws
    /// in that case so the caller aborts the save instead of overwriting data.
    func loadPlotIndexForMutation(sampleKey: String, generatedAt: Date) throws -> MeasurementPlotIndex {
        let empty = MeasurementPlotIndex(sampleKey: sampleKey, updatedAt: generatedAt)
        guard let url = try? layout.measurementPlotIndexURL(sampleKey: sampleKey) else { return empty }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let nsErr as NSError where nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
            return empty
        } catch {
            fputs("[SpinLab] LibraryChartIndexStore: measurement_plot_index unreadable, aborting save (\(sampleKey)): \(error)\n", stderr)
            throw AppError.io("measurement_plot_index unreadable at \(url.path): \(error.localizedDescription)")
        }
        guard let decoded = try? Self.decoder.decode(MeasurementPlotIndex.self, from: data) else {
            fputs("[SpinLab] LibraryChartIndexStore: measurement_plot_index corrupt, rebuilding (\(sampleKey))\n", stderr)
            return empty
        }
        return decoded
    }

    // MARK: - Fail-soft loads (Load*UseCase contract: missing/corrupt/unsupported-schema → nil)

    func loadResultsIndexFailSoft(sampleKey: String) -> WorkbenchResultsIndex? {
        guard let url = try? layout.resultsIndexURL(sampleKey: sampleKey) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsErr = error as NSError
            if nsErr.domain != NSCocoaErrorDomain || nsErr.code != NSFileReadNoSuchFileError {
                fputs("[SpinLab] LibraryChartIndexStore: results_index read error for \(sampleKey): \(error)\n", stderr)
            }
            return nil
        }
        guard let index = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: data) else {
            fputs("[SpinLab] LibraryChartIndexStore: results_index decode failed for \(sampleKey)\n", stderr)
            return nil
        }
        guard index.schemaVersion == 1 else {
            fputs("[SpinLab] LibraryChartIndexStore: unsupported results_index schema v\(index.schemaVersion) for \(sampleKey)\n", stderr)
            return nil
        }
        return index
    }

    func loadPlotIndexFailSoft(sampleKey: String) -> MeasurementPlotIndex? {
        guard let url = try? layout.measurementPlotIndexURL(sampleKey: sampleKey) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsErr = error as NSError
            if nsErr.domain != NSCocoaErrorDomain || nsErr.code != NSFileReadNoSuchFileError {
                fputs("[SpinLab] LibraryChartIndexStore: measurement_plot_index read error for \(sampleKey): \(error)\n", stderr)
            }
            return nil
        }
        guard let index = try? Self.decoder.decode(MeasurementPlotIndex.self, from: data) else {
            fputs("[SpinLab] LibraryChartIndexStore: measurement_plot_index decode failed for \(sampleKey)\n", stderr)
            return nil
        }
        guard index.schemaVersion == 1 else {
            fputs("[SpinLab] LibraryChartIndexStore: unsupported measurement_plot_index schema v\(index.schemaVersion) for \(sampleKey)\n", stderr)
            return nil
        }
        return index
    }

    // MARK: - Strict loads (destructive path: missing → nil, corrupt/unsupported schema → throw)

    /// Returns the decoded index plus its raw bytes (needed by destructive callers
    /// to build a rollback write entry), or nil if the file does not exist.
    /// Throws if the file exists but cannot be decoded, or decodes to an unsupported
    /// schemaVersion — a destructive operation must never silently rewrite a future
    /// schema's data using the current model, and must never treat either case as empty.
    func loadResultsIndexStrict(sampleKey: String) throws -> (index: WorkbenchResultsIndex, rawData: Data)? {
        let url = try layout.resultsIndexURL(sampleKey: sampleKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let index = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: data) else {
            throw AppError.io("results_index corrupt at \(url.path)")
        }
        guard index.schemaVersion == 1 else {
            throw AppError.io("results_index unsupported schema v\(index.schemaVersion) at \(url.path)")
        }
        return (index, data)
    }

    func loadPlotIndexStrict(sampleKey: String) throws -> (index: MeasurementPlotIndex, rawData: Data)? {
        let url = try layout.measurementPlotIndexURL(sampleKey: sampleKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let index = try? Self.decoder.decode(MeasurementPlotIndex.self, from: data) else {
            throw AppError.io("measurement_plot_index corrupt at \(url.path)")
        }
        guard index.schemaVersion == 1 else {
            throw AppError.io("measurement_plot_index unsupported schema v\(index.schemaVersion) at \(url.path)")
        }
        return (index, data)
    }

    // MARK: - Audit loads (.ok / .missing / .corrupt)

    /// Explicit tri-state read for audit. A corrupt index must never be treated as
    /// "empty" — doing so causes real chart files referenced by that index to be
    /// misclassified as orphans and become destructive-delete candidates.
    func loadResultsIndexForAudit(sampleKey: String) -> LibraryIndexReadStatus<WorkbenchResultsIndex> {
        guard let url = try? layout.resultsIndexURL(sampleKey: sampleKey) else { return .missing }
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .corrupt }
        guard let index = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: data) else { return .corrupt }
        return .ok(index)
    }

    // MARK: - Storage-level mutation helpers

    /// Upserts `reference` by chart identity. Returns storage facts only — the
    /// previous reference, if any — so the caller (Workbench) can decide overwrite
    /// and stale-file semantics itself.
    func upsertChartReference(
        into index: WorkbenchResultsIndex,
        reference: WorkbenchResultReference,
        updatedAt: Date
    ) -> ChartIndexMutationResult {
        var mutated = index
        var previous: WorkbenchResultReference?
        if let existingIdx = mutated.references.firstIndex(where: { $0.chartIdentityKey == reference.chartIdentityKey }) {
            previous = mutated.references[existingIdx]
            mutated.references[existingIdx] = reference
        } else {
            mutated.references.append(reference)
        }
        mutated.updatedAt = updatedAt
        return ChartIndexMutationResult(index: mutated, previousReference: previous)
    }

    func removingReference(chartIdentityKey: String, from index: WorkbenchResultsIndex, updatedAt: Date) -> WorkbenchResultsIndex {
        var mutated = index
        mutated.references.removeAll { $0.chartIdentityKey == chartIdentityKey }
        mutated.updatedAt = updatedAt
        return mutated
    }

    func removingChartKeys(_ keys: Set<String>, from plotIndex: MeasurementPlotIndex, updatedAt: Date) -> MeasurementPlotIndex {
        var mutated = plotIndex
        mutated.entries = plotIndex.entries
            .mapValues { keys.isEmpty ? $0 : $0.filter { !keys.contains($0) } }
            .filter { !$0.value.isEmpty }
        mutated.updatedAt = updatedAt
        return mutated
    }
}
