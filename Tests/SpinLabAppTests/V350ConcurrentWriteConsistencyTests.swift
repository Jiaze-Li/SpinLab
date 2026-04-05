import Foundation
import Testing
@testable import SpinLabApp

/// Concurrent write consistency tests for V3.5.
///
/// ## What `AtomicFileWriter` guarantees
/// Each write uses a unique `.spinlab-tmp-{UUID}` temp file in the destination directory,
/// fsync'd and then atomically renamed/replaced to the destination. This means:
/// - The destination file is **never partially written** — readers always see a complete,
///   parseable snapshot.
/// - Concurrent writes are serialised by the filesystem rename: exactly one writer's data
///   wins per rename; no interleaving of bytes from different writes.
///
/// ## What `AtomicFileWriter` does NOT guarantee
/// `PersistMeasurementDataUseCase` and `PersistChartArtifactUseCase` each perform a
/// read-modify-write cycle (read existing JSON → append/upsert → write). Two concurrent
/// callers that both read before either has written will both overwrite the other — the
/// last rename wins and the first writer's update is lost. This is **expected behaviour**
/// (last-write-wins), not corruption. Full mutual exclusion for RMW cycles is out of scope.
///
/// ## What these tests verify
/// 1. The on-disk file is always valid, parseable JSON after any number of concurrent writes.
/// 2. Records / references that survive are structurally complete (no partial state).
/// 3. At least one write always survives.
/// 4. Sequential writes (the happy path) preserve all records.
@Suite("V3.5.0 Concurrent Write Consistency")
struct V350ConcurrentWriteConsistencyTests {

    // MARK: - Helpers

    private func makeFixture() throws -> (resolver: LibraryPathResolver, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v350-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryPathResolver(libraryRootURL: root), root)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRecord(
        sampleKey: String,
        metric: String = "Hc",
        value: Double,
        runID: String = UUID().uuidString
    ) -> WorkbenchMetricRecord {
        // Conditions must use canonical (lowercase, trimmed) keys — Adj-8.
        WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: sampleKey,
            displayKey: sampleKey,
            workflowID: "AHE",
            metric: metric,
            value: value,
            canonicalUnit: "T",
            conditions: ["temperature": "80k"],
            generatedAt: Date(),
            runID: runID
        )
    }

    /// Each `index` produces a distinct `sourceRef`, giving a distinct `chartIdentityKey`.
    /// Without a unique `sourceRef`, all payloads hash to the same identity and upsert
    /// the same single entry — which is correct product behaviour but unhelpful for testing
    /// "all N references are retained" in the sequential baseline test.
    private func makePayload(sampleKey: String, index: Int) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Concurrent Test \(index)",
            axisMapping: WorkbenchAxisMapping(xField: "field", yField: "rxy"),
            series: [WorkbenchPlotSeries(
                label: "s\(index)",
                x: [-0.1, 0.0, 0.1],
                y: [1.0, 0.0, -1.0],
                sourceRef: "samples/\(sampleKey)/measurements/run_\(index).dat"
            )]
        )
    }

    private func decodeMeasurementStore(at relPath: String, resolver: LibraryPathResolver) throws -> WorkbenchMeasurementDataStore {
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)
    }

    private func decodeResultsIndex(at relPath: String, resolver: LibraryPathResolver) throws -> WorkbenchResultsIndex {
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchResultsIndex.self, from: data)
    }

    // MARK: - measurement_data.json: concurrent writes

    @Test("concurrent appends to measurement_data.json produce a valid, parseable file")
    func concurrentMeasurementDataWritesProduceValidJSON() async throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-CONCURRENT"
        let writeCount = 10

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<writeCount {
                group.addTask {
                    let writer = AtomicFileWriter()
                    let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
                    let record = self.makeRecord(sampleKey: sampleKey, value: Double(i) * 0.01)
                    try? useCase.execute(sampleKey: sampleKey, record: record)
                }
            }
        }

        let store = try decodeMeasurementStore(
            at: "samples/\(sampleKey)/_spinlab/measurement_data.json",
            resolver: resolver
        )
        // AtomicFileWriter's rename guarantee: the file is always a complete JSON snapshot.
        // At least one writer must have survived.
        #expect(!store.records.isEmpty, "at least one write must survive")
    }

    @Test("concurrent appends: every record present in the file is structurally complete")
    func concurrentMeasurementDataWriteRecordsAreComplete() async throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STRUCT"
        let writeCount = 8

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<writeCount {
                group.addTask {
                    let writer = AtomicFileWriter()
                    let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
                    let record = self.makeRecord(sampleKey: sampleKey, value: Double(i) * 0.01)
                    try? useCase.execute(sampleKey: sampleKey, record: record)
                }
            }
        }

        let store = try decodeMeasurementStore(
            at: "samples/\(sampleKey)/_spinlab/measurement_data.json",
            resolver: resolver
        )

        // No partial records: every record in the file must have required non-empty fields.
        for record in store.records {
            #expect(!record.recordID.isEmpty)
            #expect(record.sampleKey == sampleKey)
            #expect(!record.metric.isEmpty)
            #expect(!record.runID.isEmpty)
        }
        // latestIndex must not reference more keys than there are records.
        #expect(store.latestIndex.keys.count <= store.records.count)
    }

    /// Baseline: sequential writes must retain ALL records (no last-write-wins race).
    /// This is the contrast case — it documents why concurrent writes can lose updates.
    @Test("sequential appends to measurement_data.json retain all records")
    func sequentialMeasurementDataWritesRetainAllRecords() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-SEQUENTIAL"
        let writeCount = 8
        let writer = AtomicFileWriter()
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        for i in 0..<writeCount {
            let record = makeRecord(sampleKey: sampleKey, value: Double(i) * 0.01)
            try useCase.execute(sampleKey: sampleKey, record: record)
        }

        let store = try decodeMeasurementStore(
            at: "samples/\(sampleKey)/_spinlab/measurement_data.json",
            resolver: resolver
        )
        #expect(store.records.count == writeCount,
                "sequential writes must retain all \(writeCount) records; got \(store.records.count)")
    }

    // MARK: - results_index.json: concurrent writes

    @Test("concurrent chart persists to results_index.json produce a valid, parseable file")
    func concurrentResultsIndexWritesProduceValidJSON() async throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-IDX-CONCURRENT"
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let writeCount = 10

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<writeCount {
                group.addTask {
                    let writer = AtomicFileWriter()
                    let useCase = PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
                    let payload = self.makePayload(sampleKey: sampleKey, index: i)
                    try? useCase.execute(sampleKey: sampleKey, payload: payload, imageData: pngData)
                }
            }
        }

        let index = try decodeResultsIndex(
            at: "samples/\(sampleKey)/_spinlab/results_index.json",
            resolver: resolver
        )
        #expect(!index.references.isEmpty, "at least one chart reference must survive")
    }

    @Test("concurrent chart persists: every surviving reference has non-empty required fields")
    func concurrentResultsIndexReferencesAreComplete() async throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-IDX-STRUCT"
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let writeCount = 8

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<writeCount {
                group.addTask {
                    let writer = AtomicFileWriter()
                    let useCase = PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
                    let payload = self.makePayload(sampleKey: sampleKey, index: i)
                    try? useCase.execute(sampleKey: sampleKey, payload: payload, imageData: pngData)
                }
            }
        }

        let index = try decodeResultsIndex(
            at: "samples/\(sampleKey)/_spinlab/results_index.json",
            resolver: resolver
        )

        for ref in index.references {
            #expect(!ref.chartIdentityKey.isEmpty)
            #expect(!ref.chartImagePath.isEmpty)
            #expect(!ref.manifestPath.isEmpty)
            #expect(!ref.workflowID.isEmpty)
        }
    }

    /// Baseline: sequential chart persists must retain all references.
    @Test("sequential chart persists to results_index.json retain all references")
    func sequentialResultsIndexWritesRetainAllReferences() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-IDX-SEQUENTIAL"
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let writeCount = 6
        let writer = AtomicFileWriter()
        let useCase = PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)

        for i in 0..<writeCount {
            let payload = makePayload(sampleKey: sampleKey, index: i)
            try useCase.execute(sampleKey: sampleKey, payload: payload, imageData: pngData)
        }

        let index = try decodeResultsIndex(
            at: "samples/\(sampleKey)/_spinlab/results_index.json",
            resolver: resolver
        )
        #expect(index.references.count == writeCount,
                "sequential writes must retain all \(writeCount) references; got \(index.references.count)")
    }
}
