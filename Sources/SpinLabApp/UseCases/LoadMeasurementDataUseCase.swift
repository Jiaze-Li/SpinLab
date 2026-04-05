import Foundation

struct LoadMeasurementDataUseCase {
    let pathResolver: LibraryPathResolver

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Returns the `WorkbenchMeasurementDataStore` for `sampleKey`, or nil if the file is
    /// absent, unreadable, contains corrupt JSON, or carries an unrecognized schema version (≠ 1).
    ///
    /// Never throws — all error paths collapse to nil (fail-soft per Adj-10).
    /// Non-missing-file failures are logged to stderr to aid debugging.
    func execute(sampleKey: String) -> WorkbenchMeasurementDataStore? {
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        guard let url = try? pathResolver.absoluteURL(for: relPath) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsErr = error as NSError
            if nsErr.domain != NSCocoaErrorDomain || nsErr.code != NSFileReadNoSuchFileError {
                fputs("[SpinLab] LoadMeasurementDataUseCase: read error for \(sampleKey): \(error)\n", stderr)
            }
            return nil
        }
        guard let store = try? Self.decoder.decode(WorkbenchMeasurementDataStore.self, from: data) else {
            fputs("[SpinLab] LoadMeasurementDataUseCase: JSON decode failed for \(sampleKey)\n", stderr)
            return nil
        }
        guard store.schemaVersion == 1 else {
            fputs("[SpinLab] LoadMeasurementDataUseCase: unsupported schema v\(store.schemaVersion) for \(sampleKey)\n", stderr)
            return nil
        }
        return store
    }
}
