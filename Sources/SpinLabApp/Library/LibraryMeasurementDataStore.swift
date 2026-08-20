import Foundation

/// Sole owner of `measurement_data.json` codec and canonical path access.
///
/// Preserves the existing data-loss protection: a mutation load throws on
/// corrupt data (never silently drops records by rebuilding empty), while a
/// strict destructive load distinguishes "nothing to do" (missing) from
/// "must abort" (corrupt).
struct LibraryMeasurementDataStore {
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

    func encode(_ store: WorkbenchMeasurementDataStore) throws -> Data {
        try Self.encoder.encode(store)
    }

    /// Mutation load: missing → empty store, corrupt → throw (never overwrite
    /// existing measurement data with an empty rebuild).
    func loadForMutation(sampleKey: String) throws -> WorkbenchMeasurementDataStore {
        let url = try layout.measurementDataURL(sampleKey: sampleKey)
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(WorkbenchMeasurementDataStore.self, from: data)
        } catch let nsErr as NSError where nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileReadNoSuchFileError {
            return WorkbenchMeasurementDataStore()
        } catch {
            fputs("[SpinLab] LibraryMeasurementDataStore: read/decode failed at \(url.path): \(error)\n", stderr)
            throw AppError.io("measurement_data corrupt or unreadable at \(url.path): \(error.localizedDescription)")
        }
    }

    /// Strict destructive load: missing → nil, corrupt → throw.
    func loadStrict(sampleKey: String) throws -> WorkbenchMeasurementDataStore? {
        let url = try layout.measurementDataURL(sampleKey: sampleKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let store = try? Self.decoder.decode(WorkbenchMeasurementDataStore.self, from: data) else {
            throw AppError.io("measurement_data corrupt at \(url.path)")
        }
        guard store.schemaVersion == 1 else {
            throw AppError.io("measurement_data unsupported schema v\(store.schemaVersion) at \(url.path)")
        }
        return store
    }

    /// Fail-soft load (Load*UseCase contract): missing/corrupt/unsupported-schema → nil.
    func loadFailSoft(sampleKey: String) -> WorkbenchMeasurementDataStore? {
        guard let url = try? layout.measurementDataURL(sampleKey: sampleKey) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsErr = error as NSError
            if nsErr.domain != NSCocoaErrorDomain || nsErr.code != NSFileReadNoSuchFileError {
                fputs("[SpinLab] LibraryMeasurementDataStore: read error for \(sampleKey): \(error)\n", stderr)
            }
            return nil
        }
        guard let store = try? Self.decoder.decode(WorkbenchMeasurementDataStore.self, from: data) else {
            fputs("[SpinLab] LibraryMeasurementDataStore: JSON decode failed for \(sampleKey)\n", stderr)
            return nil
        }
        guard store.schemaVersion == 1 else {
            fputs("[SpinLab] LibraryMeasurementDataStore: unsupported schema v\(store.schemaVersion) for \(sampleKey)\n", stderr)
            return nil
        }
        return store
    }
}
