import Foundation
import Testing
@testable import SpinLabApp

// TestRecord architecture Phase 1: recompute preservation rules.
// Covers regression cases G and H from the Phase 1 implementation spec.

@Suite("TestRecord Phase 1 — Recompute preserves measurementTimestamp")
struct TestRecordPhase1RecomputeTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func makeSampleDirectory(measurementFileName: String, measurementContents: String) throws -> (sampleDirectory: URL, measurementURL: URL, sidecarURL: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-recompute-\(UUID().uuidString)", isDirectory: true)
        let measurementsDir = tmp.appendingPathComponent("measurements/General", isDirectory: true)
        try FileManager.default.createDirectory(at: measurementsDir, withIntermediateDirectories: true)
        let measurementURL = measurementsDir.appendingPathComponent(measurementFileName)
        try Data(measurementContents.utf8).write(to: measurementURL)
        let sidecarURL = measurementURL.deletingPathExtension()
            .appendingPathExtension(measurementURL.pathExtension + ".spinlab.json")
        return (tmp, measurementURL, sidecarURL)
    }

    private func baseSidecar(
        sourceFilePath: String,
        sampleKey: String?,
        measurementTimestamp: SidecarMeasurementTimestamp?
    ) -> SpinLabFileSidecar {
        SpinLabFileSidecar(
            workflow: "ahe",
            workflowDisplayName: "AHE",
            channels: ["file"],
            sourceFilePath: sourceFilePath,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 1,
                ruleSetFingerprint: "fp-before-recompute",
                appliedAt: Date(timeIntervalSince1970: 1_700_000_000),
                fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
            ),
            sampleKey: sampleKey,
            measurementTimestamp: measurementTimestamp
        )
    }

    private func loadResult() -> RuleLoader.LoadResult {
        RuleLoader().loadFromBundleOnly()
    }

    private func loadSidecar(at url: URL) throws -> SpinLabFileSidecar {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SpinLabFileSidecar.self, from: Data(contentsOf: url))
    }

    // MARK: - G: recompute preserves an existing measurementTimestamp

    @Test("recompute preserves an existing measurementTimestamp unchanged")
    func recomputePreservesExistingTimestamp() throws {
        let (sampleDirectory, measurementURL, sidecarURL) = try makeSampleDirectory(
            measurementFileName: "sample4.lvm",
            measurementContents: "Tableau:\n1\t2\t3"
        )
        defer { try? FileManager.default.removeItem(at: sampleDirectory) }

        let originalTimestamp = SidecarMeasurementTimestamp(
            value: Date(timeIntervalSince1970: 1_650_000_000),
            provenance: .filename,
            rawText: "20220415000000"
        )
        let existing = baseSidecar(
            sourceFilePath: measurementURL.path,
            sampleKey: "sample4",
            measurementTimestamp: originalTimestamp
        )
        try encoder.encode(existing).write(to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        _ = service.recomputeSidecars(in: sampleDirectory, sampleKey: "sample4", loadResult: loadResult())

        let recomputed = try loadSidecar(at: sidecarURL)
        #expect(recomputed.measurementTimestamp == originalTimestamp)
        #expect(recomputed.sampleKey == "sample4")
    }

    // MARK: - H: recompute never replaces instrumentHeader timestamp with filesystemFallback

    @Test("recompute never downgrades instrumentHeader timestamp to filesystemFallback")
    func recomputeNeverDowngradesProvenance() throws {
        // Measurement file itself has no FILEOPENTIME/filename-prefix timestamp signal,
        // so a naive re-resolution against it would fall back to filesystemFallback.
        let (sampleDirectory, measurementURL, sidecarURL) = try makeSampleDirectory(
            measurementFileName: "sample5.lvm",
            measurementContents: "Tableau:\n1\t2\t3"
        )
        defer { try? FileManager.default.removeItem(at: sampleDirectory) }

        let originalTimestamp = SidecarMeasurementTimestamp(
            value: Date(timeIntervalSince1970: 1_650_000_000),
            provenance: .instrumentHeader,
            rawText: "3/18/2026,1:24 PM"
        )
        let existing = baseSidecar(
            sourceFilePath: measurementURL.path,
            sampleKey: "sample5",
            measurementTimestamp: originalTimestamp
        )
        try encoder.encode(existing).write(to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        _ = service.recomputeSidecars(in: sampleDirectory, sampleKey: "sample5", loadResult: loadResult())

        let recomputed = try loadSidecar(at: sidecarURL)
        #expect(recomputed.measurementTimestamp?.provenance == .instrumentHeader)
        #expect(recomputed.measurementTimestamp == originalTimestamp)
    }

    // MARK: - Backfill: recompute fills in a measurementTimestamp when the old sidecar has none

    @Test("recompute backfills measurementTimestamp when old sidecar predates the field")
    func recomputeBackfillsMissingTimestamp() throws {
        let (sampleDirectory, measurementURL, sidecarURL) = try makeSampleDirectory(
            measurementFileName: "sample6.dat",
            measurementContents: """
            [Header]
            FILEOPENTIME,38091212.03,3/18/2026,1:24 PM
            [Data]
            Temperature (K),Bridge 1 Resistance (Ohms)
            170.0,100.0
            """
        )
        defer { try? FileManager.default.removeItem(at: sampleDirectory) }

        let existing = baseSidecar(sourceFilePath: measurementURL.path, sampleKey: "sample6", measurementTimestamp: nil)
        try encoder.encode(existing).write(to: sidecarURL)

        let service = LibrarySidecarService(libraryStore: LibraryStore())
        _ = service.recomputeSidecars(in: sampleDirectory, sampleKey: "sample6", loadResult: loadResult())

        let recomputed = try loadSidecar(at: sidecarURL)
        #expect(recomputed.measurementTimestamp?.provenance == .instrumentHeader)
        #expect(recomputed.sampleKey == "sample6")
    }
}
