import Foundation

/// Sole owner of on-disk artifact/index path layout under the Library root.
///
/// `LibraryArtifactLayout` knows WHERE things live (relative-path templates for
/// `_spinlab` indexes, chart directories, and the deleted-charts archive) and
/// composes `LibraryPathResolver` for root-escape safety. It does not know
/// filename generation, chart identity, or JSON schema — those stay with
/// Workbench domain code and `LibraryChartIndexStore`/`LibraryMeasurementDataStore`.
struct LibraryArtifactLayout {
    let pathResolver: LibraryPathResolver

    init(pathResolver: LibraryPathResolver) {
        self.pathResolver = pathResolver
    }

    init(libraryRootURL: URL) {
        self.pathResolver = LibraryPathResolver(libraryRootURL: libraryRootURL)
    }

    // MARK: - Relative paths

    func resultsIndexRelativePath(sampleKey: String) -> String {
        "samples/\(sampleKey)/_spinlab/results_index.json"
    }

    func measurementPlotIndexRelativePath(sampleKey: String) -> String {
        "samples/\(sampleKey)/_spinlab/measurement_plot_index.json"
    }

    func measurementDataRelativePath(sampleKey: String) -> String {
        "samples/\(sampleKey)/_spinlab/measurement_data.json"
    }

    func singleSampleChartDirectoryRelativePath(sampleKey: String) -> String {
        "samples/\(sampleKey)/charts"
    }

    func multiSampleChartDirectoryRelativePath() -> String {
        "_spinlab/multi-sample/charts"
    }

    private func chartDirectoryRelativePath(sampleKeys: [String]) -> String {
        sampleKeys.count > 1
            ? multiSampleChartDirectoryRelativePath()
            : singleSampleChartDirectoryRelativePath(sampleKey: sampleKeys.first ?? "unknown")
    }

    func chartImageRelativePath(fileName: String, sampleKeys: [String]) -> String {
        "\(chartDirectoryRelativePath(sampleKeys: sampleKeys))/\(fileName).png"
    }

    func chartManifestRelativePath(fileName: String, sampleKeys: [String]) -> String {
        "\(chartDirectoryRelativePath(sampleKeys: sampleKeys))/\(fileName).manifest.json"
    }

    // MARK: - Absolute URLs

    func resultsIndexURL(sampleKey: String) throws -> URL {
        try pathResolver.absoluteURL(for: resultsIndexRelativePath(sampleKey: sampleKey))
    }

    func measurementPlotIndexURL(sampleKey: String) throws -> URL {
        try pathResolver.absoluteURL(for: measurementPlotIndexRelativePath(sampleKey: sampleKey))
    }

    func measurementDataURL(sampleKey: String) throws -> URL {
        try pathResolver.absoluteURL(for: measurementDataRelativePath(sampleKey: sampleKey))
    }

    func samplesRootURL() -> URL {
        pathResolver.libraryRootURL.appending(path: "samples")
    }

    // MARK: - Deleted chart archive

    /// Directory that holds archived copies of a deleted chart's image/manifest,
    /// derived from the chart's own resolved absolute image URL (works for both
    /// single-sample and multi-sample chart directories without needing sampleKeys).
    func deletedChartArchiveDirectoryURL(forChartImageURL imageURL: URL, folderName: String) -> URL {
        let chartDirectoryURL = imageURL.deletingLastPathComponent()
        let archiveRootURL = chartDirectoryURL.deletingLastPathComponent()
            .appending(path: "deleted-charts", directoryHint: .isDirectory)
        return archiveRootURL.appending(path: folderName, directoryHint: .isDirectory)
    }
}
