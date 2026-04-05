import Foundation

struct LoadWorkbenchResultsUseCase {
    let pathResolver: LibraryPathResolver

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Returns the `WorkbenchResultsIndex` for `sampleKey`, or nil if the file is absent,
    /// unreadable, contains corrupt JSON, or carries an unrecognized schema version (≠ 1).
    ///
    /// Never throws — all error paths are collapsed to nil (fail-soft per Adj-10).
    func execute(sampleKey: String) -> WorkbenchResultsIndex? {
        let relPath = "samples/\(sampleKey)/_spinlab/results_index.json"
        guard let url = try? pathResolver.absoluteURL(for: relPath),
              let data = try? Data(contentsOf: url),
              let index = try? Self.decoder.decode(WorkbenchResultsIndex.self, from: data),
              index.schemaVersion == 1 else {
            return nil
        }
        return index
    }
}
