import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixture

/// Self-contained temp directory that mirrors a Library's `samples/` layout.
private struct FixtureDelete {
    let rootURL: URL
    let resolver: LibraryPathResolver
    private let fm = FileManager.default

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v343-delete-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }

    // MARK: - Helpers

    /// Creates `samples/{sampleKey}/_spinlab/results_index.json` with the given references.
    func writeResultsIndex(sampleKey: String, references: [WorkbenchResultReference]) throws {
        let index = WorkbenchResultsIndex(sampleKey: sampleKey, updatedAt: Date(), references: references)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Creates `samples/{sampleKey}/_spinlab/measurement_plot_index.json` with the given entries.
    func writePlotIndex(sampleKey: String, entries: [String: [String]]) throws {
        let index = MeasurementPlotIndex(sampleKey: sampleKey, updatedAt: Date(), entries: entries)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/measurement_plot_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Writes corrupt (non-JSON) bytes to results_index.json.
    func writeCorruptResultsIndex(sampleKey: String) throws {
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<<<NOT JSON>>>".utf8).write(to: url)
    }

    /// Creates a dummy chart PNG so we can verify deletion.
    func writeChartFile(relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("PNG".utf8).write(to: url)
    }

    func fileExists(relativePath: String) -> Bool {
        guard let url = try? resolver.absoluteURL(for: relativePath) else { return false }
        return fm.fileExists(atPath: url.path)
    }

    func loadResultsIndex(sampleKey: String) -> WorkbenchResultsIndex? {
        LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
    }

    func loadPlotIndex(sampleKey: String) -> MeasurementPlotIndex? {
        LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
    }
}

private func makeRef(
    key: String = "chart-A",
    imagePath: String = "samples/S1/charts/chart-A.png",
    manifestPath: String = "samples/S1/charts/chart-A.manifest.json"
) -> WorkbenchResultReference {
    WorkbenchResultReference(
        chartIdentityKey: key,
        chartImagePath: imagePath,
        manifestPath: manifestPath,
        workflowID: "wf-1",
        generatedAt: Date()
    )
}

// MARK: - Happy path

@Suite("deleteWorkbenchResult — happy path")
struct DeleteWorkbenchResultHappyPath {

    @Test("removes reference from results_index and deletes chart files")
    func removesRefAndFiles() throws {
        let f = try FixtureDelete()
        defer { f.cleanup() }

        let refA = makeRef()
        let refB = makeRef(key: "chart-B", imagePath: "samples/S1/charts/chart-B.png",
                           manifestPath: "samples/S1/charts/chart-B.manifest.json")
        try f.writeResultsIndex(sampleKey: "S1", references: [refA, refB])
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)

        let success = LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(refA, rootURL: f.rootURL)

        #expect(success)
        // results_index should retain refB but not refA
        let idx = f.loadResultsIndex(sampleKey: "S1")
        #expect(idx != nil)
        #expect(idx?.references.count == 1)
        #expect(idx?.references.first?.chartIdentityKey == "chart-B")
        // chart files should be gone
        #expect(!f.fileExists(relativePath: refA.chartImagePath))
        #expect(!f.fileExists(relativePath: refA.manifestPath))
    }

    @Test("cleans measurement_plot_index.json on disk after delete")
    func cleansPlotIndexOnDisk() throws {
        let f = try FixtureDelete()
        defer { f.cleanup() }

        let refA = makeRef()
        try f.writeResultsIndex(sampleKey: "S1", references: [refA])
        try f.writePlotIndex(sampleKey: "S1", entries: [
            "data1.txt": ["chart-A", "chart-B"],
            "data2.txt": ["chart-A"]
        ])
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)

        let success = LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(refA, rootURL: f.rootURL)
        #expect(success)

        let plotIdx = f.loadPlotIndex(sampleKey: "S1")
        #expect(plotIdx != nil)
        // "chart-A" removed; "data1.txt" retains only "chart-B"; "data2.txt" dropped (empty)
        #expect(plotIdx?.entries.count == 1)
        #expect(plotIdx?.entries["data1.txt"] == ["chart-B"])
        #expect(plotIdx?.entries["data2.txt"] == nil)
    }

    @Test("succeeds when measurement_plot_index.json is absent")
    func succeedsWithoutPlotIndex() throws {
        let f = try FixtureDelete()
        defer { f.cleanup() }

        let refA = makeRef()
        try f.writeResultsIndex(sampleKey: "S1", references: [refA])
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)
        // No plot index file created

        let success = LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(refA, rootURL: f.rootURL)
        #expect(success)
        #expect(!f.fileExists(relativePath: refA.chartImagePath))
    }
}

// MARK: - Fail-closed

@Suite("deleteWorkbenchResult — fail-closed on corrupt index")
struct DeleteWorkbenchResultFailClosed {

    @Test("aborts when results_index.json is corrupt — files untouched")
    func abortsOnCorruptIndex() throws {
        let f = try FixtureDelete()
        defer { f.cleanup() }

        let refA = makeRef()
        try f.writeCorruptResultsIndex(sampleKey: "S1")
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)

        let success = LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(refA, rootURL: f.rootURL)

        #expect(!success)
        // Chart files must NOT be deleted — fail-closed
        #expect(f.fileExists(relativePath: refA.chartImagePath))
        #expect(f.fileExists(relativePath: refA.manifestPath))
    }

    @Test("aborts when ANY sample has corrupt index, even if other samples are clean")
    func abortsOnAnyCorruptSample() throws {
        let f = try FixtureDelete()
        defer { f.cleanup() }

        let refA = makeRef()
        // S1 is valid and references chart-A
        try f.writeResultsIndex(sampleKey: "S1", references: [refA])
        // S2 is corrupt
        try f.writeCorruptResultsIndex(sampleKey: "S2")
        try f.writeChartFile(relativePath: refA.chartImagePath)

        let success = LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(refA, rootURL: f.rootURL)

        #expect(!success)
        // Even S1's index should be unchanged — atomic abort
        let idx = f.loadResultsIndex(sampleKey: "S1")
        #expect(idx?.references.count == 1)
        #expect(f.fileExists(relativePath: refA.chartImagePath))
    }
}

// MARK: - Multi-sample

@Suite("deleteWorkbenchResult — multi-sample cleanup")
struct DeleteWorkbenchResultMultiSample {

    @Test("cleans both results_index and plot_index across multiple samples")
    func cleansAcrossSamples() throws {
        let f = try FixtureDelete()
        defer { f.cleanup() }

        let refA = makeRef()
        let refA2 = makeRef(key: "chart-A",
                            imagePath: "samples/S2/charts/chart-A.png",
                            manifestPath: "samples/S2/charts/chart-A.manifest.json")

        // Both S1 and S2 reference chart-A
        try f.writeResultsIndex(sampleKey: "S1", references: [refA])
        try f.writeResultsIndex(sampleKey: "S2", references: [refA2])
        try f.writePlotIndex(sampleKey: "S1", entries: ["data.txt": ["chart-A"]])
        try f.writePlotIndex(sampleKey: "S2", entries: ["data.txt": ["chart-A", "chart-C"]])
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)

        let success = LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(refA, rootURL: f.rootURL)
        #expect(success)

        // S1: results_index empty, plot_index entry dropped
        let idx1 = f.loadResultsIndex(sampleKey: "S1")
        #expect(idx1?.references.isEmpty == true)
        let plot1 = f.loadPlotIndex(sampleKey: "S1")
        #expect(plot1?.entries.isEmpty == true)

        // S2: results_index empty, plot_index retains chart-C
        let idx2 = f.loadResultsIndex(sampleKey: "S2")
        #expect(idx2?.references.isEmpty == true)
        let plot2 = f.loadPlotIndex(sampleKey: "S2")
        #expect(plot2?.entries["data.txt"] == ["chart-C"])
    }
}
