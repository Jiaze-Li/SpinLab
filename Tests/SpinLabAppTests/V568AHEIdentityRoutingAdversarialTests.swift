import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.8 — Adversarial verification that the AHE hit → selection → series identity
/// path (historically prone to sample/channel cross-contamination) is closed end to end.
///
/// Unlike `V323AHESeriesOrderTests` (which hand-builds `AHEPlotSelectionItem`s directly)
/// and `V537AHESearchSnapshotConsumptionTests` (which stops at the guard boundary before
/// the async analysis body runs), this suite drives the full public entry point —
/// `AHEWorkspaceStore.runAnalysis(selectedHitsSnapshot:)` — with two DIFFERENT hits
/// (different sampleKey, different channel, different source file, different numeric
/// content per file) and asserts the resulting `ingestionResult.series` binds each
/// sample's identity to its own numeric data, not the other sample's.
@Suite("V5.6.8 AHE identity routing — adversarial")
struct V568AHEIdentityRoutingAdversarialTests {

    private struct Fixture {
        let rootURL: URL
        let fm = FileManager.default

        init() throws {
            rootURL = fm.temporaryDirectory.appending(
                path: "spinlab-v568-ahe-identity-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        func write(name: String, content: String) throws -> URL {
            let url = rootURL.appending(path: name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func cleanup() { try? fm.removeItem(at: rootURL) }
    }

    private static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    /// Bridge 1 resistance values distinct and identifiable: 100.0 / 90.0 / 80.0
    private static let sampleAContent = """
    [Header]
    TITLE, sampleA
    [Data]
    \(colHeader)
    ,0,4449,10.0,10000.0,0,,,,,,,,,,,,,25,100.0,,,
    ,1,4449,10.0,5000.0,0,,,,,,,,,,,,,25,90.0,,,
    ,2,4449,10.0,-5000.0,0,,,,,,,,,,,,,25,80.0,,,
    """

    /// Bridge 2 resistance values distinct and identifiable: -7.0 / -6.0 / -5.0
    /// (different magnitude AND sign from sample A's bridge 1 values, to catch any swap.)
    private static let sampleBContent = """
    [Header]
    TITLE, sampleB
    [Data]
    \(colHeader)
    ,0,4449,20.0,10000.0,0,,,,,,,,,,,,,25,,-7.0,,
    ,1,4449,20.0,5000.0,0,,,,,,,,,,,,,25,,-6.0,,
    ,2,4449,20.0,-5000.0,0,,,,,,,,,,,,,25,,-5.0,,
    """

    private func makeHit(sidecarPath: String, measurementFilePath: String, sourceFilePath: String, sampleKey: String, batchID: String, channel: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: measurementFilePath,
            sourceFilePath: sourceFilePath,
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe",
            batchID: batchID,
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: [:],
            channels: [channel],
            appliedAt: .distantPast
        )
    }

    @MainActor
    @Test("Two different samples on different channels/files do not cross-contaminate identity or data through the full runAnalysis path")
    func twoDistinctSamplesDoNotCrossContaminate() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let urlA = try fixture.write(name: "sampleA.dat", content: Self.sampleAContent)
        let urlB = try fixture.write(name: "sampleB.dat", content: Self.sampleBContent)

        let hitA = makeHit(
            sidecarPath: "/tmp/sampleA.spinlab.json",
            measurementFilePath: urlA.path,
            sourceFilePath: urlA.path,
            sampleKey: "PN10|o|STO|111",
            batchID: "PN10",
            channel: "ch1"
        )
        let hitB = makeHit(
            sidecarPath: "/tmp/sampleB.spinlab.json",
            measurementFilePath: urlB.path,
            sourceFilePath: urlB.path,
            sampleKey: "PN20|b|STO|999",
            batchID: "PN20",
            channel: "ch2"
        )

        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .ahe,
            queryText: "PN10 PN20",
            selectedIDs: Set([hitA.id, hitB.id]),
            selectedHits: [hitA, hitB],
            sourceHitCount: 2,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)
        #expect(store.isPlotRendering == true)

        var ingestion: AHEIngestionResult?
        for _ in 0..<80 {
            if let result = store.ingestionResult, result.series.count == 2 {
                ingestion = result
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let result = try #require(ingestion, "Timed out waiting for AHE analysis to complete")

        let seriesA = try #require(result.series.first(where: { $0.sampleID == "PN10|o|STO|111" }))
        let seriesB = try #require(result.series.first(where: { $0.sampleID == "PN20|b|STO|999" }))

        // Identity: each series' label/sourceRef/metadata must reference its OWN sample/file,
        // never the other sample's.
        #expect(seriesA.label.contains("PN10|o|STO|111"))
        #expect(seriesA.label.contains("ch1"))
        #expect(!seriesA.label.contains("PN20"))
        #expect(seriesA.sourceRef == urlA.path)
        #expect(seriesA.metadata["sampleKey"] == "PN10|o|STO|111")

        #expect(seriesB.label.contains("PN20|b|STO|999"))
        #expect(seriesB.label.contains("ch2"))
        #expect(!seriesB.label.contains("PN10"))
        #expect(seriesB.sourceRef == urlB.path)
        #expect(seriesB.metadata["sampleKey"] == "PN20|b|STO|999")

        // Data content: sample A's y-values must be its own Bridge 1 resistances
        // (100/90/80), NOT sample B's Bridge 2 values (-7/-6/-5) — the exact failure
        // mode a channel/sample swap would produce.
        let sortedA = seriesA.y.sorted()
        #expect(sortedA.contains(where: { abs($0 - 80.0) < 0.001 }))
        #expect(sortedA.contains(where: { abs($0 - 100.0) < 0.001 }))
        #expect(!seriesA.y.contains(where: { $0 < 0 }))

        let sortedB = seriesB.y.sorted()
        #expect(sortedB.contains(where: { abs($0 - (-7.0)) < 0.001 }))
        #expect(sortedB.contains(where: { abs($0 - (-5.0)) < 0.001 }))
        #expect(!seriesB.y.contains(where: { $0 > 0 }))

        // Series identity keys must differ and must not collide.
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: result.series)
        #expect(Set(identities.map(\.identityKey)).count == 2)
    }

    @MainActor
    @Test("A single hit with multiple channels fans out into per-channel series without sample identity drift")
    func multiChannelHitFansOutWithoutDrift() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        // Single file with BOTH bridges active, single sample, two channels.
        let content = """
        [Header]
        TITLE, dual
        [Data]
        \(Self.colHeader)
        ,0,4449,10.0,10000.0,0,,,,,,,,,,,,,25,11.0,21.0,,
        ,1,4449,10.0,5000.0,0,,,,,,,,,,,,,25,12.0,22.0,,
        ,2,4449,10.0,-5000.0,0,,,,,,,,,,,,,25,13.0,23.0,,
        """
        let url = try fixture.write(name: "dual.dat", content: content)

        let hit = makeHit(
            sidecarPath: "/tmp/dual.spinlab.json",
            measurementFilePath: url.path,
            sourceFilePath: url.path,
            sampleKey: "PN30|o|STO|111",
            batchID: "PN30",
            channel: "ch1"
        )
        // Override channels to report BOTH bridges present on this one hit.
        var multiChannelHit = hit
        multiChannelHit.channels = ["ch1", "ch2"]

        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: .ahe,
            queryText: "PN30",
            selectedIDs: Set([multiChannelHit.id]),
            selectedHits: [multiChannelHit],
            sourceHitCount: 1,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)

        var ingestion: AHEIngestionResult?
        for _ in 0..<80 {
            if let result = store.ingestionResult, result.series.count == 2 {
                ingestion = result
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let result = try #require(ingestion, "Timed out waiting for multi-channel AHE analysis to complete")

        let ch1Series = try #require(result.series.first(where: { $0.label.contains("ch1") }))
        let ch2Series = try #require(result.series.first(where: { $0.label.contains("ch2") }))

        // Both channels share the same sample identity (same hit) but must carry
        // distinct, correctly-bound bridge data.
        #expect(ch1Series.sampleID == "PN30|o|STO|111")
        #expect(ch2Series.sampleID == "PN30|o|STO|111")
        #expect(ch1Series.y.sorted().contains(where: { abs($0 - 11.0) < 0.001 }))
        #expect(ch2Series.y.sorted().contains(where: { abs($0 - 21.0) < 0.001 }))

        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: result.series)
        #expect(Set(identities.map(\.identityKey)).count == 2, "per-channel series must have distinct identity keys despite sharing one hit")
    }
}
