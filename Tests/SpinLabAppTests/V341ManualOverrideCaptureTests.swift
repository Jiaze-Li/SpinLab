import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.4.1 Manual Override Capture")
struct V341ManualOverrideCaptureTests {

    // MARK: - Helpers

    private func makeFixture() throws -> (resolver: LibraryPathResolver, writer: AtomicFileWriter, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v341-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryPathResolver(libraryRootURL: root), AtomicFileWriter(), root)
    }

    private func cleanup(_ root: URL) { try? FileManager.default.removeItem(at: root) }

    private func readStore(sampleKey: String, resolver: LibraryPathResolver) throws -> WorkbenchMeasurementDataStore {
        let url = try resolver.absoluteURL(for: "samples/\(sampleKey)/_spinlab/measurement_data.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchMeasurementDataStore.self, from: data)
    }

    private func persist(
        sampleKey: String,
        extractedValue: Double,
        override: WorkbenchMetricOverrideCandidate?,
        resolver: LibraryPathResolver,
        writer: AtomicFileWriter
    ) throws {
        let runID = UUID().uuidString
        let generatedAt = Date()

        let storedValue: Double
        let overrideInfo: WorkbenchMetricOverrideInfo?
        if let o = override {
            storedValue = o.proposedValue
            overrideInfo = WorkbenchMetricOverrideInfo(
                oldValue: extractedValue,
                newValue: o.proposedValue,
                reason: o.reason,
                source: o.source,
                at: generatedAt
            )
        } else {
            storedValue = extractedValue
            overrideInfo = nil
        }

        let record = WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: sampleKey,
            displayKey: sampleKey,
            workflowID: "AHE",
            metric: "Hc",
            value: storedValue,
            canonicalUnit: "T",
            conditions: [:],
            generatedAt: generatedAt,
            runID: runID,
            overrideInfo: overrideInfo
        )
        try PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKey: sampleKey, record: record)
    }

    // MARK: - No override → overrideInfo is nil

    @Test("no override: persisted record has nil overrideInfo")
    func noOverrideProducesNilOverrideInfo() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        try persist(sampleKey: "SK-A", extractedValue: 0.05, override: nil,
                    resolver: resolver, writer: writer)

        let store = try readStore(sampleKey: "SK-A", resolver: resolver)
        #expect(store.records.first?.overrideInfo == nil)
        #expect(store.records.first?.value == 0.05)
    }

    // MARK: - Override set → overrideInfo fields correct

    @Test("override set: overrideInfo.oldValue, newValue, reason, source, at are correct")
    func overrideFieldsCorrect() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let candidate = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.08,
            reason: "Visual inspection correction",
            source: .manual
        )
        try persist(sampleKey: "SK-B", extractedValue: 0.05, override: candidate,
                    resolver: resolver, writer: writer)

        let store = try readStore(sampleKey: "SK-B", resolver: resolver)
        let info = store.records.first?.overrideInfo
        #expect(info != nil)
        #expect(info?.oldValue == 0.05)
        #expect(info?.newValue == 0.08)
        #expect(info?.reason == "Visual inspection correction")
        #expect(info?.source == .manual)
    }

    // MARK: - source == .manual for user-entered correction

    @Test("user-entered override has source == .manual")
    func overrideSourceIsManual() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let candidate = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.07,
            reason: "Recheck",
            source: .manual
        )
        try persist(sampleKey: "SK-C", extractedValue: 0.05, override: candidate,
                    resolver: resolver, writer: writer)

        let store = try readStore(sampleKey: "SK-C", resolver: resolver)
        #expect(store.records.first?.overrideInfo?.source == .manual)
    }

    // MARK: - latestIndex reflects override value, not extracted value

    @Test("latestIndex stores override value, not raw extracted value")
    func latestIndexUsesOverrideValue() throws {
        let (resolver, writer, root) = try makeFixture()
        defer { cleanup(root) }

        let candidate = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.09,
            reason: "Corrected",
            source: .manual
        )
        try persist(sampleKey: "SK-D", extractedValue: 0.05, override: candidate,
                    resolver: resolver, writer: writer)

        let store = try readStore(sampleKey: "SK-D", resolver: resolver)
        let pointer = store.latestIndex.values.first
        #expect(pointer?.value == 0.09)
    }

    // MARK: - Override cleared after successful persist (store behaviour)

    @Test("pendingMetricOverride is cleared by clearPlot")
    @MainActor
    func overrideClearedByClearPlot() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.pendingMetricOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.05, reason: "test", source: .manual
        )
        #expect(store.pendingMetricOverride != nil)
        store.clearPlot()
        #expect(store.pendingMetricOverride == nil)
    }

    // MARK: - OverrideSource round-trips through JSON

    @Test("OverrideSource encodes and decodes correctly for all cases")
    func overrideSourceRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for source in [OverrideSource.manual, .import, .recompute] {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(OverrideSource.self, from: data)
            #expect(decoded == source)
        }
    }
}
