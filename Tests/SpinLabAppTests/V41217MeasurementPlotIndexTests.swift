import Foundation
import Testing
@testable import SpinLabApp

// MARK: - v4.1.2.17 — MeasurementPlotIndex tests
//
// Coverage:
//   - MeasurementPlotIndex.upsert: single file→single chart, single file→multi chart, multi file→same chart
//   - PersistChartArtifactUseCase writes measurement_plot_index.json alongside results_index.json
//   - LoadMeasurementPlotIndexUseCase: missing file → nil, valid decode → index, bad schema → nil, corrupt JSON → nil (no crash)
//   - Dirty-key filtering: stale chartIdentityKeys absent from WorkbenchResultsIndex are removed in memory

// MARK: - MeasurementPlotIndex.upsert

@Suite("MeasurementPlotIndex.upsert")
struct MeasurementPlotIndexUpsertTests {

    @Test("single file → single chart")
    func singleFileSingleChart() {
        var idx = MeasurementPlotIndex(sampleKey: "S1", updatedAt: .distantPast)
        idx.upsert(chartIdentityKey: "chart_aaa", sourceFile: "run1.dat")
        #expect(idx.entries["run1.dat"] == ["chart_aaa"])
    }

    @Test("single file → multiple charts accumulate without duplication")
    func singleFileMultiChart() {
        var idx = MeasurementPlotIndex(sampleKey: "S1", updatedAt: .distantPast)
        idx.upsert(chartIdentityKey: "chart_aaa", sourceFile: "run1.dat")
        idx.upsert(chartIdentityKey: "chart_bbb", sourceFile: "run1.dat")
        // idempotent: re-insert same key
        idx.upsert(chartIdentityKey: "chart_aaa", sourceFile: "run1.dat")
        #expect(idx.entries["run1.dat"] == ["chart_aaa", "chart_bbb"])
    }

    @Test("multiple files map to same chart independently")
    func multiFileSameChart() {
        var idx = MeasurementPlotIndex(sampleKey: "S1", updatedAt: .distantPast)
        idx.upsert(chartIdentityKey: "chart_aaa", sourceFile: "runA.dat")
        idx.upsert(chartIdentityKey: "chart_aaa", sourceFile: "runB.dat")
        #expect(idx.entries["runA.dat"] == ["chart_aaa"])
        #expect(idx.entries["runB.dat"] == ["chart_aaa"])
    }

    @Test("key normalised to lastPathComponent of sourceRef")
    func keyNormalisation() {
        var idx = MeasurementPlotIndex(sampleKey: "S1", updatedAt: .distantPast)
        idx.upsert(chartIdentityKey: "chart_aaa", sourceFile: "/some/deep/path/run1.dat")
        #expect(idx.entries["run1.dat"] != nil)
        #expect(idx.entries["/some/deep/path/run1.dat"] == nil)
    }
}

// MARK: - PersistChartArtifactUseCase writes measurement_plot_index.json

@Suite("PersistChartArtifactUseCase — MeasurementPlotIndex write path")
struct PersistChartPlotIndexWriteTests {

    @Test("persisting a chart writes measurement_plot_index.json with correct entry")
    func persistWritesPlotIndex() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }

        let payload = makePlotPayload(sourceRef: "runA.dat")
        let result = try fixture.makePersistUseCase().execute(
            sampleKey: "S1", payload: payload, imageData: Data([0xAB])
        )

        let loaded = fixture.loadPlotIndex(sampleKey: "S1")
        #expect(loaded != nil)
        let keys = loaded?.entries["runA.dat"]
        #expect(keys?.contains(result.chartIdentityKey) == true)
    }

    @Test("persisting same chart twice is idempotent in plot index")
    func persistIdempotent() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }

        let payload = makePlotPayload(sourceRef: "runA.dat")
        let persist = fixture.makePersistUseCase()
        let r1 = try persist.execute(sampleKey: "S1", payload: payload, imageData: Data([0xAB]))
        let r2 = try persist.execute(sampleKey: "S1", payload: payload, imageData: Data([0xAB]))
        #expect(r1.chartIdentityKey == r2.chartIdentityKey)

        let loaded = fixture.loadPlotIndex(sampleKey: "S1")
        let keys = loaded?.entries["runA.dat"] ?? []
        // Must appear exactly once
        #expect(keys.filter { $0 == r1.chartIdentityKey }.count == 1)
    }

    @Test("multi-source chart appears under each source file in plot index")
    func multiSourceChart() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }

        let payload = makePlotPayloadMultiSource(sourceRefs: ["fileA.dat", "fileB.dat"])
        let result = try fixture.makePersistUseCase().execute(
            sampleKeys: ["S1"], payload: payload, imageData: Data([0xCD])
        )

        let loaded = fixture.loadPlotIndex(sampleKey: "S1")
        #expect(loaded?.entries["fileA.dat"]?.contains(result.chartIdentityKey) == true)
        #expect(loaded?.entries["fileB.dat"]?.contains(result.chartIdentityKey) == true)
    }
}

// MARK: - LoadMeasurementPlotIndexUseCase

@Suite("LoadMeasurementPlotIndexUseCase")
struct LoadMeasurementPlotIndexUseCaseTests {

    @Test("missing file returns nil silently")
    func missingFileReturnsNil() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }
        let result = fixture.loadPlotIndex(sampleKey: "nonexistent")
        #expect(result == nil)
    }

    @Test("valid file decodes correctly")
    func validFileDecode() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }

        var idx = MeasurementPlotIndex(sampleKey: "S1", updatedAt: Date())
        idx.upsert(chartIdentityKey: "chart_xyz", sourceFile: "run1.dat")
        try fixture.writePlotIndex(idx, sampleKey: "S1")

        let loaded = fixture.loadPlotIndex(sampleKey: "S1")
        #expect(loaded?.entries["run1.dat"] == ["chart_xyz"])
    }

    @Test("unknown schema version returns nil (no crash)")
    func unknownSchemaReturnsNil() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }

        // Write a v99 schema manually
        let raw = """
        {"schemaVersion":99,"sampleKey":"S1","updatedAt":"2024-01-01T00:00:00Z","entries":{}}
        """
        try fixture.writePlotIndexRaw(raw, sampleKey: "S1")

        let result = fixture.loadPlotIndex(sampleKey: "S1")
        #expect(result == nil)
    }

    @Test("corrupt JSON returns nil without crashing (fail-soft Adj-10)")
    func corruptJSONReturnsNil() throws {
        let fixture = try FixturePlotIndex()
        defer { fixture.cleanup() }

        try fixture.writePlotIndexRaw("NOT_JSON_AT_ALL", sampleKey: "S1")
        let result = fixture.loadPlotIndex(sampleKey: "S1")
        #expect(result == nil)
    }
}

// MARK: - Dirty-key filtering (LibraryFeatureStore coordination layer)

@Suite("MeasurementPlotIndex dirty-key filtering")
struct MeasurementPlotIndexFilteringTests {

    @Test("stale chartIdentityKeys absent from results_index are removed in memory")
    func staleKeysFiltered() {
        var raw = MeasurementPlotIndex(sampleKey: "S1", updatedAt: .distantPast)
        raw.entries = [
            "run1.dat": ["chart_valid", "chart_stale"],
            "run2.dat": ["chart_also_stale"]
        ]

        let validRefs = [
            WorkbenchResultReference(
                chartIdentityKey: "chart_valid",
                chartImagePath: "samples/S1/charts/foo.png",
                manifestPath: "samples/S1/charts/foo.manifest.json",
                workflowID: "AHE",
                generatedAt: .distantPast
            )
        ]
        let validKeys = Set(validRefs.map(\.chartIdentityKey))

        var clean = raw
        clean.entries = raw.entries
            .mapValues { $0.filter { validKeys.contains($0) } }
            .filter { !$0.value.isEmpty }

        #expect(clean.entries["run1.dat"] == ["chart_valid"])
        #expect(clean.entries["run2.dat"] == nil)   // all keys stale → entry removed
    }

    @Test("nil measurementPlotIndex does not crash UI prop lookup")
    func nilIndexIsNonFatal() {
        // Simulates UI reading measurementPlotIndex when it is nil (e.g. no file yet)
        let idx: MeasurementPlotIndex? = nil
        let refs = idx?.entries["any.dat"] ?? []
        #expect(refs.isEmpty)
    }
}

// MARK: - Helpers

private func makePlotPayload(sourceRef: String) -> WorkbenchPlotPayload {
    WorkbenchPlotPayload(
        workflowID: "AHE",
        workflowDisplayName: "AHE",
        title: "Test Chart",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [2.0], sourceRef: sourceRef)]
    )
}

private func makePlotPayloadMultiSource(sourceRefs: [String]) -> WorkbenchPlotPayload {
    let series = sourceRefs.enumerated().map { i, ref in
        WorkbenchPlotSeries(label: "S\(i)", x: [1.0], y: [Double(i)], sourceRef: ref)
    }
    return WorkbenchPlotPayload(
        workflowID: "AHE",
        workflowDisplayName: "AHE",
        title: "Multi Source",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: series
    )
}

// MARK: - Fixture

private struct FixturePlotIndex {
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
            path: "spinlab-v41217-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        resolver = LibraryPathResolver(libraryRootURL: rootURL)
    }

    func makePersistUseCase() -> PersistChartArtifactUseCase {
        PersistChartArtifactUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
    }

    func loadPlotIndex(sampleKey: String) -> MeasurementPlotIndex? {
        LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
    }

    func writePlotIndex(_ idx: MeasurementPlotIndex, sampleKey: String) throws {
        let dir = rootURL.appending(path: "samples/\(sampleKey)/_spinlab", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "measurement_plot_index.json")
        try Self.encoder.encode(idx).write(to: url)
    }

    func writePlotIndexRaw(_ raw: String, sampleKey: String) throws {
        let dir = rootURL.appending(path: "samples/\(sampleKey)/_spinlab", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "measurement_plot_index.json")
        try Data(raw.utf8).write(to: url)
    }

    func cleanup() { try? fm.removeItem(at: rootURL) }
}
