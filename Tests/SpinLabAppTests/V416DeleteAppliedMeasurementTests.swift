import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixture

/// Self-contained temp directory mirroring both `batches/` and root `samples/` layouts.
private struct FixtureMeasurementDelete {
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
            path: "spinlab-v416-delete-measurement-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }

    // MARK: - Batch-level helpers

    /// Creates a measurement data file + sidecar under `batches/<prefix>/<batchID>/samples/<sampleKey>/measurements/<workflow>/`.
    /// Returns the sidecar absolute path (used as `AppliedMeasurement.id`).
    @discardableResult
    func writeMeasurementFiles(
        prefix: String = "A",
        batchID: String = "batch1",
        sampleKey: String,
        workflow: String = "AHE",
        fileName: String
    ) throws -> String {
        let sampleDir = rootURL
            .appending(path: "batches/\(prefix)/\(batchID)/samples/\(sampleKey)/measurements/\(workflow)")
        try fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let dataFileURL = sampleDir.appending(path: fileName)
        try Data("measurement data".utf8).write(to: dataFileURL)
        let sidecarURL = sampleDir.appending(path: "\(fileName).spinlab.json")
        let sidecar = SpinLabFileSidecar(
            workflow: workflow,
            workflowDisplayName: workflow,
            conditions: [:],
            channels: [],
            sourceFilePath: "/original/\(fileName)",
            appliedAt: Date()
        )
        let data = try Self.encoder.encode(sidecar)
        try data.write(to: sidecarURL)
        return sidecarURL.path
    }

    /// Returns the batch-level sample directory URL.
    func batchSampleDir(
        prefix: String = "A",
        batchID: String = "batch1",
        sampleKey: String
    ) -> URL {
        rootURL.appending(path: "batches/\(prefix)/\(batchID)/samples/\(sampleKey)")
    }

    // MARK: - Root-level helpers

    func writeResultsIndex(sampleKey: String, references: [WorkbenchResultReference]) throws {
        let index = WorkbenchResultsIndex(sampleKey: sampleKey, updatedAt: Date(), references: references)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func writePlotIndex(sampleKey: String, entries: [String: [String]]) throws {
        let index = MeasurementPlotIndex(sampleKey: sampleKey, updatedAt: Date(), entries: entries)
        let data = try Self.encoder.encode(index)
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/measurement_plot_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func writeCorruptResultsIndex(sampleKey: String) throws {
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/results_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<<<NOT JSON>>>".utf8).write(to: url)
    }

    func writeCorruptPlotIndex(sampleKey: String) throws {
        let url = rootURL.appending(path: "samples/\(sampleKey)/_spinlab/measurement_plot_index.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<<<NOT JSON>>>".utf8).write(to: url)
    }

    func writeChartFile(relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("PNG".utf8).write(to: url)
    }

    func writeMeasurementSets(sampleKey: String, sets: [MeasurementSet], prefix: String = "A", batchID: String = "batch1") throws {
        let sampleDir = batchSampleDir(prefix: prefix, batchID: batchID, sampleKey: sampleKey)
        let url = sampleDir.appending(path: "measurement_sets.json")
        try fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(sets)
        try data.write(to: url)
    }

    func fileExists(absolutePath: String) -> Bool {
        fm.fileExists(atPath: absolutePath)
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

    func loadMeasurementSets(sampleKey: String, prefix: String = "A", batchID: String = "batch1") -> [MeasurementSet] {
        let url = batchSampleDir(prefix: prefix, batchID: batchID, sampleKey: sampleKey)
            .appending(path: "measurement_sets.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MeasurementSet].self, from: data)) ?? []
    }
}

private func makeMeasurement(
    sidecarPath: String,
    workflow: String = "AHE",
    sourceFileName: String = "run1.dat"
) -> AppliedMeasurement {
    AppliedMeasurement(
        id: sidecarPath,
        workflow: workflow,
        workflowDisplayName: workflow,
        conditions: [:],
        appliedAt: Date(),
        sourceFileName: sourceFileName
    )
}

private func makeRef(
    key: String,
    sampleKey: String = "S1",
    imagePath: String? = nil,
    manifestPath: String? = nil
) -> WorkbenchResultReference {
    WorkbenchResultReference(
        chartIdentityKey: key,
        chartImagePath: imagePath ?? "samples/\(sampleKey)/charts/\(key).png",
        manifestPath: manifestPath ?? "samples/\(sampleKey)/charts/\(key).manifest.json",
        workflowID: "ahe",
        generatedAt: Date()
    )
}

// MARK: - Happy path

@Suite("deleteAppliedMeasurement — happy path")
struct DeleteAppliedMeasurementHappyPath {

    @Test("deletes sidecar and data file")
    func deletesSidecarAndDataFile() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        let dataFilePath = sidecarPath.replacingOccurrences(of: ".spinlab.json", with: "")
        let m = makeMeasurement(sidecarPath: sidecarPath)

        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        #expect(!f.fileExists(absolutePath: sidecarPath))
        #expect(!f.fileExists(absolutePath: dataFilePath))
    }

    @Test("cascade-deletes associated charts via measurement_plot_index")
    func cascadeDeletesCharts() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        let refA = makeRef(key: "chart-A", sampleKey: "S1")
        let refB = makeRef(key: "chart-B", sampleKey: "S1")
        try f.writeResultsIndex(sampleKey: "S1", references: [refA, refB])
        try f.writePlotIndex(sampleKey: "S1", entries: ["run1.dat": ["chart-A"]])
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)
        try f.writeChartFile(relativePath: refB.chartImagePath)
        try f.writeChartFile(relativePath: refB.manifestPath)

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        // chart-A (linked to run1.dat) should be deleted
        #expect(!f.fileExists(relativePath: refA.chartImagePath))
        #expect(!f.fileExists(relativePath: refA.manifestPath))
        // chart-B (not linked to run1.dat) should survive
        #expect(f.fileExists(relativePath: refB.chartImagePath))
        // results_index should retain only refB
        let idx = f.loadResultsIndex(sampleKey: "S1")
        #expect(idx?.references.count == 1)
        #expect(idx?.references.first?.chartIdentityKey == "chart-B")
    }

    @Test("removes sourceFileName from measurement sets and drops empty sets")
    func cleansMeasurementSets() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        let set1 = MeasurementSet(id: "set1", name: "Set A", workflow: "AHE",
                                  memberFileNames: ["run1.dat", "run2.dat"], createdAt: Date())
        let set2 = MeasurementSet(id: "set2", name: "Set B", workflow: "AHE",
                                  memberFileNames: ["run1.dat"], createdAt: Date())
        try f.writeMeasurementSets(sampleKey: "S1", sets: [set1, set2])

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        let remaining = f.loadMeasurementSets(sampleKey: "S1")
        // set1 retains run2.dat; set2 (now empty) should be removed
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == "set1")
        #expect(remaining.first?.memberFileNames == ["run2.dat"])
    }
}

// MARK: - Non-fatal missing files

@Suite("deleteAppliedMeasurement — non-fatal missing files")
struct DeleteAppliedMeasurementNonFatal {

    @Test("succeeds when data file is already absent")
    func succeedsWithMissingDataFile() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        // Remove the data file manually
        let dataFilePath = sidecarPath.replacingOccurrences(of: ".spinlab.json", with: "")
        try FileManager.default.removeItem(atPath: dataFilePath)

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        #expect(!f.fileExists(absolutePath: sidecarPath))
    }

    @Test("succeeds when sidecar is already absent")
    func succeedsWithMissingSidecar() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        // Remove sidecar manually
        try FileManager.default.removeItem(atPath: sidecarPath)

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        // Data file should still be deleted
        let dataFilePath = sidecarPath.replacingOccurrences(of: ".spinlab.json", with: "")
        #expect(!f.fileExists(absolutePath: dataFilePath))
    }

    @Test("succeeds when no charts exist (measurement_plot_index absent)")
    func succeedsWithNoCharts() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        // No root-level _spinlab/ at all

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        #expect(!f.fileExists(absolutePath: sidecarPath))
    }
}

// MARK: - Fail-closed on corrupt index

@Suite("deleteAppliedMeasurement — fail-closed on corrupt index")
struct DeleteAppliedMeasurementFailClosed {

    @Test("aborts when results_index.json is corrupt — measurement files untouched")
    func abortsOnCorruptResultsIndex() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        try f.writePlotIndex(sampleKey: "S1", entries: ["run1.dat": ["chart-A"]])
        try f.writeCorruptResultsIndex(sampleKey: "S1")

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(!success)
        // Sidecar and data file must NOT be deleted
        #expect(f.fileExists(absolutePath: sidecarPath))
        let dataFilePath = sidecarPath.replacingOccurrences(of: ".spinlab.json", with: "")
        #expect(f.fileExists(absolutePath: dataFilePath))
    }

    @Test("aborts when measurement_plot_index.json is corrupt — measurement files untouched")
    func abortsOnCorruptPlotIndex() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        let sidecarPath = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        try f.writeCorruptPlotIndex(sampleKey: "S1")

        let m = makeMeasurement(sidecarPath: sidecarPath)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(!success)
        #expect(f.fileExists(absolutePath: sidecarPath))
    }
}

// MARK: - Cross-sample isolation

@Suite("deleteAppliedMeasurement — cross-sample isolation")
struct DeleteAppliedMeasurementIsolation {

    @Test("does not affect same-named file in a different sample")
    func isolatesBySample() throws {
        let f = try FixtureMeasurementDelete()
        defer { f.cleanup() }

        // S1 and S2 both have run1.dat
        let sidecarPathS1 = try f.writeMeasurementFiles(sampleKey: "S1", fileName: "run1.dat")
        let sidecarPathS2 = try f.writeMeasurementFiles(sampleKey: "S2", fileName: "run1.dat")

        // Only S1's plot index links run1.dat to a chart
        let refA = makeRef(key: "chart-A", sampleKey: "S1")
        try f.writeResultsIndex(sampleKey: "S1", references: [refA])
        try f.writePlotIndex(sampleKey: "S1", entries: ["run1.dat": ["chart-A"]])
        try f.writeChartFile(relativePath: refA.chartImagePath)
        try f.writeChartFile(relativePath: refA.manifestPath)

        // S2 has its own chart
        let refB = makeRef(key: "chart-B", sampleKey: "S2")
        try f.writeResultsIndex(sampleKey: "S2", references: [refB])
        try f.writePlotIndex(sampleKey: "S2", entries: ["run1.dat": ["chart-B"]])
        try f.writeChartFile(relativePath: refB.chartImagePath)
        try f.writeChartFile(relativePath: refB.manifestPath)

        // Delete S1's measurement only
        let m = makeMeasurement(sidecarPath: sidecarPathS1)
        let success = LibraryFeatureStore.deleteAppliedMeasurementOnDisk(m, rootURL: f.rootURL)

        #expect(success)
        // S1: sidecar, data, chart all gone
        #expect(!f.fileExists(absolutePath: sidecarPathS1))
        #expect(!f.fileExists(relativePath: refA.chartImagePath))
        // S2: everything intact
        #expect(f.fileExists(absolutePath: sidecarPathS2))
        let dataPathS2 = sidecarPathS2.replacingOccurrences(of: ".spinlab.json", with: "")
        #expect(f.fileExists(absolutePath: dataPathS2))
        #expect(f.fileExists(relativePath: refB.chartImagePath))
        let idx2 = f.loadResultsIndex(sampleKey: "S2")
        #expect(idx2?.references.count == 1)
    }
}
