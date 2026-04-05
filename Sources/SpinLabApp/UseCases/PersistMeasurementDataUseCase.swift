import Foundation

/// Outcome of a single render-and-persist cycle.
///
/// Returned by `AHEWorkspaceStore` after each `renderAHEPlot(persistArtifact: true)` call.
/// Surfaces partial failures (chart OK but metric write failed) so the UI can reflect them
/// instead of silently swallowing errors (replaces `try?` pattern — Adj-3).
enum PersistenceOutcome: Sendable {
    case success(trace: WorkbenchRunTraceProjection)
    case partial(trace: WorkbenchRunTraceProjection?, metricError: String)
    case failure(String)

    var trace: WorkbenchRunTraceProjection? {
        switch self {
        case .success(let t): return t
        case .partial(let t, _): return t
        case .failure: return nil
        }
    }
}

// MARK: -

/// A pre-persist correction entered by the user before committing a metric to Library.
///
/// Owned by `AHEWorkspaceStore.pendingMetricOverride`. When non-nil, the stored metric
/// record will contain a `WorkbenchMetricOverrideInfo` with `source = .manual`.
struct WorkbenchMetricOverrideCandidate: Equatable, Sendable {
    /// The corrected value the user wants to store instead of the auto-extracted value.
    var proposedValue: Double
    /// Free-text reason for the correction (shown in future audit UI).
    var reason: String
    /// How this override was produced. Defaults to `.manual` for user-entered corrections.
    var source: OverrideSource
}

// MARK: -

struct PersistMeasurementDataUseCase {
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

    /// Appends `record` to the sample's `measurement_data.json` and updates `latestIndex`.
    ///
    /// The file is written atomically via `AtomicFileWriter`. If the file does not yet
    /// exist, a fresh `WorkbenchMeasurementDataStore` is created.
    ///
    /// - Important: Condition keys in `record.conditions` must be **canonical** keys,
    ///   not alias keys. `WorkbenchMetricIdentity.makeIdentityKey` normalises (lowercase/trim)
    ///   but does not resolve aliases. The caller is responsible for canonical input (Adj-8).
    func execute(sampleKey: String, record: WorkbenchMetricRecord) throws {
        guard record.sampleKey == sampleKey else {
            throw AppError.validation(
                "sampleKey mismatch: path key '\(sampleKey)' does not match record.sampleKey '\(record.sampleKey)'"
            )
        }
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let absURL = try pathResolver.absoluteURL(for: relPath)

        var store: WorkbenchMeasurementDataStore
        if let data = try? Data(contentsOf: absURL),
           let decoded = try? Self.decoder.decode(WorkbenchMeasurementDataStore.self, from: data) {
            store = decoded
        } else {
            store = WorkbenchMeasurementDataStore()
        }

        store.append(record)
        let encoded = try Self.encoder.encode(store)
        try writer.write(encoded, to: absURL)
    }
}
