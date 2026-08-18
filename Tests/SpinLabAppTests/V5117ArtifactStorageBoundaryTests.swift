import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixture

private struct StorageBoundaryFixture {
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
            path: "spinlab-v5117-boundary-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }

    func writeManifest(_ manifest: WorkbenchRunManifest, relativePath: String) throws {
        let url = try resolver.absoluteURL(for: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(manifest).write(to: url)
    }

    func rawPlotIndexData(sampleKey: String) -> Data? {
        guard let url = try? resolver.absoluteURL(for: "samples/\(sampleKey)/_spinlab/measurement_plot_index.json") else { return nil }
        return try? Data(contentsOf: url)
    }

    func plotIndexPath(sampleKey: String) -> String {
        "samples/\(sampleKey)/_spinlab/measurement_plot_index.json"
    }
}

// MARK: - Failing writer (simulates a mid-write crash)

private struct FailingWriter: AtomicFileWritingCapability {
    func commit(_ entries: [AtomicWriteEntry]) throws {
        throw AppError.io("simulated failure")
    }
    func write(_ data: Data, to destinationURL: URL) throws {
        throw AppError.io("simulated failure")
    }
}

// MARK: - Backfill durability (Phase B)

@Suite("V5.1.17 BackfillMeasurementPlotIndex — atomic write durability")
struct V5117BackfillAtomicWriteTests {

    @Test("Backfill result is unchanged from manifest-derived entries")
    func backfillProducesCorrectEntries() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }

        let manifest = WorkbenchRunManifest(
            manifestID: "m1", runID: "r1", workflowID: "threeOmega",
            inputFiles: ["run1.lvm"], filters: [:],
            axisMapping: WorkbenchAxisMapping(xField: "T", yField: "R"),
            semanticParams: [:], outputImagePath: "samples/S1/charts/chart1.png",
            generatedAt: Date(), appVersion: "test")
        try fix.writeManifest(manifest, relativePath: "samples/S1/charts/chart1.manifest.json")

        let ref = WorkbenchResultReference(
            chartIdentityKey: "chart_abc123", chartImagePath: "samples/S1/charts/chart1.png",
            manifestPath: "samples/S1/charts/chart1.manifest.json", workflowID: "threeOmega",
            generatedAt: Date(), tabKey: nil)
        let results = WorkbenchResultsIndex(sampleKey: "S1", updatedAt: Date(), references: [ref])

        let index = BackfillMeasurementPlotIndexUseCase(pathResolver: fix.resolver)
            .execute(sampleKey: "S1", results: results)

        #expect(index?.entries["run1.lvm"] == ["chart_abc123"])

        let onDisk = LoadMeasurementPlotIndexUseCase(pathResolver: fix.resolver).execute(sampleKey: "S1")
        #expect(onDisk?.entries["run1.lvm"] == ["chart_abc123"])
    }

    @Test("Backfill uses AtomicFileWritingCapability — a failing writer leaves no index file behind")
    func backfillUsesAtomicWriter() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }

        let results = WorkbenchResultsIndex(sampleKey: "S2", updatedAt: Date(), references: [])
        _ = BackfillMeasurementPlotIndexUseCase(pathResolver: fix.resolver, writer: FailingWriter())
            .execute(sampleKey: "S2", results: results)

        // A failing atomic writer must never leave a partial/truncated file on disk —
        // this is only true if the write path actually goes through AtomicFileWriter's
        // write-to-temp-then-rename sequence rather than a direct Data.write(to:).
        #expect(fix.rawPlotIndexData(sampleKey: "S2") == nil)
    }

    @Test("Backfill never leaves a truncated/partial index when the write fails")
    func backfillFailureDoesNotCorruptExistingIndex() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }

        // Seed an existing valid index first, using the real atomic writer.
        let seedResults = WorkbenchResultsIndex(sampleKey: "S3", updatedAt: Date(), references: [])
        _ = BackfillMeasurementPlotIndexUseCase(pathResolver: fix.resolver).execute(sampleKey: "S3", results: seedResults)
        let before = fix.rawPlotIndexData(sampleKey: "S3")
        #expect(before != nil)

        // A subsequent failing write must not corrupt or truncate the existing file.
        _ = BackfillMeasurementPlotIndexUseCase(pathResolver: fix.resolver, writer: FailingWriter())
            .execute(sampleKey: "S3", results: seedResults)

        let after = fix.rawPlotIndexData(sampleKey: "S3")
        #expect(after == before)
    }
}

// MARK: - LibraryChartIndexStore (Phase A)

@Suite("V5.1.17 LibraryChartIndexStore — read policy")
struct V5117ChartIndexStoreTests {

    @Test("Mutation load: missing file returns empty index, not nil")
    func mutationLoadMissingReturnsEmpty() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }
        let store = LibraryChartIndexStore(layout: LibraryArtifactLayout(pathResolver: fix.resolver))

        let index = store.loadResultsIndexForMutation(sampleKey: "SNEW", generatedAt: Date())
        #expect(index.references.isEmpty)
        #expect(index.sampleKey == "SNEW")
    }

    @Test("Mutation load: corrupt file rebuilds empty (never throws)")
    func mutationLoadCorruptRebuildsEmpty() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }
        let layout = LibraryArtifactLayout(pathResolver: fix.resolver)
        let url = try layout.resultsIndexURL(sampleKey: "SBAD")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = LibraryChartIndexStore(layout: layout)
        let index = store.loadResultsIndexForMutation(sampleKey: "SBAD", generatedAt: Date())
        #expect(index.references.isEmpty)
    }

    @Test("Strict load: missing file returns nil")
    func strictLoadMissingReturnsNil() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }
        let store = LibraryChartIndexStore(layout: LibraryArtifactLayout(pathResolver: fix.resolver))

        let result = try store.loadResultsIndexStrict(sampleKey: "SNEW")
        #expect(result == nil)
    }

    @Test("Strict load: corrupt file throws")
    func strictLoadCorruptThrows() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }
        let layout = LibraryArtifactLayout(pathResolver: fix.resolver)
        let url = try layout.resultsIndexURL(sampleKey: "SBAD")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = LibraryChartIndexStore(layout: layout)
        #expect(throws: (any Error).self) {
            try store.loadResultsIndexStrict(sampleKey: "SBAD")
        }
    }

    @Test("upsertChartReference reports previous reference as a storage fact, without opining on overwrite/stale")
    func upsertReportsPreviousReferenceOnly() throws {
        let fix = try StorageBoundaryFixture()
        defer { fix.cleanup() }
        let store = LibraryChartIndexStore(layout: LibraryArtifactLayout(pathResolver: fix.resolver))

        let original = WorkbenchResultReference(
            chartIdentityKey: "chart_x", chartImagePath: "samples/S1/charts/old.png",
            manifestPath: "samples/S1/charts/old.manifest.json", workflowID: "threeOmega",
            generatedAt: Date(), tabKey: nil)
        let index = WorkbenchResultsIndex(sampleKey: "S1", updatedAt: Date(), references: [original])

        let replacement = WorkbenchResultReference(
            chartIdentityKey: "chart_x", chartImagePath: "samples/S1/charts/new.png",
            manifestPath: "samples/S1/charts/new.manifest.json", workflowID: "threeOmega",
            generatedAt: Date(), tabKey: nil)

        let result = store.upsertChartReference(into: index, reference: replacement, updatedAt: Date())

        #expect(result.previousReference?.chartImagePath == "samples/S1/charts/old.png")
        #expect(result.index.references.count == 1)
        #expect(result.index.references[0].chartImagePath == "samples/S1/charts/new.png")
    }
}
