import Foundation

struct LoadMeasurementDataUseCase {
    let pathResolver: LibraryPathResolver

    /// Returns the `WorkbenchMeasurementDataStore` for `sampleKey`, or nil if the file is
    /// absent, unreadable, contains corrupt JSON, or carries an unrecognized schema version (≠ 1).
    ///
    /// Never throws — all error paths collapse to nil (fail-soft per Adj-10).
    /// Non-missing-file failures are logged to stderr to aid debugging.
    func execute(sampleKey: String) -> WorkbenchMeasurementDataStore? {
        let store = LibraryMeasurementDataStore(layout: LibraryArtifactLayout(pathResolver: pathResolver))
        return store.loadFailSoft(sampleKey: sampleKey)
    }
}
