import Foundation

struct LoadMeasurementPlotIndexUseCase {
    let pathResolver: LibraryPathResolver

    /// Returns the `MeasurementPlotIndex` for `sampleKey`, or nil if the file is absent,
    /// unreadable, contains corrupt JSON, or carries an unrecognized schema version (≠ 1).
    ///
    /// Never throws — fail-soft per Adj-10.
    /// Missing file → nil (silent). Decode failure or unknown schema → fputs stderr + nil.
    func execute(sampleKey: String) -> MeasurementPlotIndex? {
        let store = LibraryChartIndexStore(layout: LibraryArtifactLayout(pathResolver: pathResolver))
        return store.loadPlotIndexFailSoft(sampleKey: sampleKey)
    }
}
