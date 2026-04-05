import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.4.0 Measurement Data Write Path")
struct V340MeasurementDataWritePathTests {

    // MARK: - Helpers

    private func makeFixture() throws -> (resolver: LibraryPathResolver, writer: AtomicFileWriter, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v340-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resolver = LibraryPathResolver(libraryRootURL: root)
        return (resolver, AtomicFileWriter(), root)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRecord(
        sampleKey: String = "PN20-STO001",
        metric: String = "Hc",
        value: Double = 0.05,
        conditions: [String: String] = ["temperature": "80K"],
        runID: String = UUID().uuidString
    ) -> WorkbenchMetricRecord {
        WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: sampleKey,
            displayKey: sampleKey,
            workflowID: "AHE",
            metric: metric,
            value: value,
            canonicalUnit: "T",
            conditions: conditions,
            generatedAt: Date(),
            runID: runID
        )
    }

    // MARK: - Round-trip

    @Test("round-trip: appended record is present after decode, latestIndex updated")
    func roundTrip() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STO001"
        let record = makeRecord(sampleKey: sampleKey, value: 0.05)
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        try useCase.execute(sampleKey: sampleKey, record: record)

        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)

        #expect(store.records.count == 1)
        #expect(store.records[0].recordID == record.recordID)
        #expect(store.records[0].value == 0.05)
        #expect(!store.latestIndex.isEmpty)
    }

    // MARK: - latestIndex deduplication

    @Test("same metric identity key appended twice: latestIndex shows only latest value")
    func latestIndexDeduplication() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STO002"
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        let first = makeRecord(sampleKey: sampleKey, value: 0.04, conditions: ["temperature": "80K"])
        let second = makeRecord(sampleKey: sampleKey, value: 0.06, conditions: ["temperature": "80K"])

        try useCase.execute(sampleKey: sampleKey, record: first)
        try useCase.execute(sampleKey: sampleKey, record: second)

        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)

        // Both records are in history, but latestIndex has only one entry for this identity
        #expect(store.records.count == 2)
        #expect(store.latestIndex.count == 1)
        let pointer = store.latestIndex.values.first
        #expect(pointer?.value == 0.06)
        #expect(pointer?.recordID == second.recordID)
    }

    // MARK: - Different condition keys produce separate latestIndex entries

    @Test("different condition values produce separate latestIndex entries")
    func differentConditionsSeparateEntries() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STO003"
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        let at80K = makeRecord(sampleKey: sampleKey, value: 0.05, conditions: ["temperature": "80K"])
        let at300K = makeRecord(sampleKey: sampleKey, value: 0.03, conditions: ["temperature": "300K"])

        try useCase.execute(sampleKey: sampleKey, record: at80K)
        try useCase.execute(sampleKey: sampleKey, record: at300K)

        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)

        #expect(store.records.count == 2)
        #expect(store.latestIndex.count == 2)
    }

    // MARK: - runID shared between chart and metric

    @Test("runID in metric record matches the runID passed by caller")
    func runIDShared() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STO004"
        let sharedRunID = UUID().uuidString
        let record = makeRecord(sampleKey: sampleKey, runID: sharedRunID)
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        try useCase.execute(sampleKey: sampleKey, record: record)

        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)

        #expect(store.records.first?.runID == sharedRunID)
    }

    // MARK: - Path uses Library-root-relative format

    @Test("use case writes to library-root-relative path resolved via LibraryPathResolver")
    func pathIsLibraryRootRelative() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STO005"
        let record = makeRecord(sampleKey: sampleKey)
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        try useCase.execute(sampleKey: sampleKey, record: record)

        let expectedRelPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let expectedAbsURL = try resolver.absoluteURL(for: expectedRelPath)
        #expect(FileManager.default.fileExists(atPath: expectedAbsURL.path))
    }

    // MARK: - PersistenceOutcome.partial on metric write failure

    @Test("PersistenceOutcome.partial emitted when metric write throws: use case propagates error")
    func partialOutcomeOnMetricFailure() throws {
        let (resolver, _, root) = try makeFixture()
        defer { cleanup(root) }

        // FailingWriter simulates a disk-full or permission error on every write.
        // PersistMeasurementDataUseCase must propagate the error so the store
        // can surface a .partial outcome to the UI (Adj-3).
        struct FailingWriter: AtomicFileWritingCapability {
            func commit(_ entries: [AtomicWriteEntry]) throws {
                throw AppError.io("Simulated write failure")
            }
            func write(_ data: Data, to destinationURL: URL) throws {
                throw AppError.io("Simulated write failure")
            }
        }

        let record = makeRecord()
        let useCase = PersistMeasurementDataUseCase(writer: FailingWriter(), pathResolver: resolver)
        #expect(throws: (any Error).self) {
            try useCase.execute(sampleKey: "PN20-STO006", record: record)
        }
    }

    // MARK: - Canonical key rule (Adj-8)

    @Test("alias condition key and canonical key produce different latestIndex entries (alias not resolved at storage layer)")
    func canonicalKeyRule() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-STO007"
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        // "device" and "angle" are different canonical keys at the storage layer.
        // Alias resolution is display-layer only — storage must not conflate them.
        let withDevice = makeRecord(sampleKey: sampleKey, value: 0.05, conditions: ["device": "30deg"])
        let withAngle = makeRecord(sampleKey: sampleKey, value: 0.05, conditions: ["angle": "30deg"])

        try useCase.execute(sampleKey: sampleKey, record: withDevice)
        try useCase.execute(sampleKey: sampleKey, record: withAngle)

        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let absURL = try resolver.absoluteURL(for: relPath)
        let data = try Data(contentsOf: absURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)

        // Storage layer treats "device" and "angle" as distinct keys — two separate entries
        #expect(store.latestIndex.count == 2)
    }

    // MARK: - sampleKey consistency guard (Fix-2)

    @Test("execute throws when record.sampleKey does not match path sampleKey")
    func sampleKeyMismatchThrows() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let record = makeRecord(sampleKey: "PN20-CORRECT")
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)

        #expect(throws: (any Error).self) {
            // Passing a different sampleKey as the path key — must throw, not silently misplace data
            try useCase.execute(sampleKey: "PN20-WRONG", record: record)
        }
    }

    // MARK: - Multi-sample metric write (Fix-1)

    @Test("multi-sample render: each sampleKey gets its own measurement_data.json entry")
    func multiSampleEachGetsMetric() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKeys = ["PN20-A", "PN20-B", "PN20-C"]
        let useCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
        let sharedRunID = UUID().uuidString

        for sk in sampleKeys {
            let record = makeRecord(sampleKey: sk, runID: sharedRunID)
            try useCase.execute(sampleKey: sk, record: record)
        }

        for sk in sampleKeys {
            let relPath = "samples/\(sk)/_spinlab/measurement_data.json"
            let absURL = try resolver.absoluteURL(for: relPath)
            let data = try Data(contentsOf: absURL)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)
            #expect(store.records.count == 1, "Expected 1 record for \(sk)")
            #expect(store.records.first?.runID == sharedRunID)
        }
    }

    // MARK: - runID end-to-end: manifest and metric share the same runID (Fix-4)

    @Test("manifest runID matches metric record runID from the same render cycle")
    func runIDEndToEndShared() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let sampleKey = "PN20-E2E"
        let sharedRunID = UUID().uuidString
        let generatedAt = Date()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])

        // Build a minimal payload
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "E2E Test",
            axisMapping: WorkbenchAxisMapping(xField: "field", yField: "rxy"),
            series: [WorkbenchPlotSeries(label: "s1", x: [-0.1, 0.0, 0.1], y: [1.0, 0.0, -1.0],
                                         sourceRef: "samples/\(sampleKey)/measurements/A/test.dat")]
        )

        // Persist chart with shared runID
        let chartResult = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKey: sampleKey, payload: payload, imageData: pngData,
                     runID: sharedRunID, generatedAt: generatedAt)

        // Persist metric with same shared runID
        let record = makeRecord(sampleKey: sampleKey, runID: sharedRunID)
        try PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKey: sampleKey, record: record)

        // Verify manifest runID
        #expect(chartResult.manifest.runID == sharedRunID)

        // Verify metric record runID from disk
        let metricPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"
        let metricURL = try resolver.absoluteURL(for: metricPath)
        let metricData = try Data(contentsOf: metricURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(WorkbenchMeasurementDataStore.self, from: metricData)

        #expect(store.records.first?.runID == sharedRunID)
        #expect(chartResult.manifest.runID == store.records.first?.runID)
    }
}
