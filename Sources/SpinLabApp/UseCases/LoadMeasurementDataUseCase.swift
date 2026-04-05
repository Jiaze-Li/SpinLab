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
    func execute(sampleKey: String) -> WorkbenchMeasurementDataStore? {
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        guard let url = try? pathResolver.absoluteURL(for: relPath),
              let data = try? Data(contentsOf: url),
              let store = try? Self.decoder.decode(WorkbenchMeasurementDataStore.self, from: data),
              store.schemaVersion == 1 else {
            return nil
        }
        return store
    }
}
