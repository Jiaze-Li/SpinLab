import Foundation

struct LoadWorkbenchResultsUseCase {
    let pathResolver: LibraryPathResolver

    /// Returns the `WorkbenchResultsIndex` for `sampleKey`, or nil if the file is absent,
    /// unreadable, contains corrupt JSON, or carries an unrecognized schema version (≠ 1).
    ///
    /// Never throws — all error paths are collapsed to nil (fail-soft per Adj-10).
    /// Non-missing-file failures are logged to stderr to aid debugging.
    func execute(sampleKey: String) -> WorkbenchResultsIndex? {
        let store = LibraryChartIndexStore(layout: LibraryArtifactLayout(pathResolver: pathResolver))
        return store.loadResultsIndexFailSoft(sampleKey: sampleKey)
    }
}
