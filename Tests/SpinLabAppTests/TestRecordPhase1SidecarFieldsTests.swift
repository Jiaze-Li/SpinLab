import Foundation
import Testing
@testable import SpinLabApp

// TestRecord architecture Phase 1: SpinLabFileSidecar.sampleKey write path + backward compat.
// Covers regression cases A, B, F from the Phase 1 implementation spec.

@MainActor
@Suite("TestRecord Phase 1 — Sidecar sampleKey")
struct TestRecordPhase1SidecarFieldsTests {

    // MARK: - A: new import writes RouteTarget.sampleId into sidecar.sampleKey

    @Test("new import writes RouteTarget.sampleId into sidecar.sampleKey")
    func newImportWritesSampleKey() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN70"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "PN70_RT_1mA.dat", contents: "single-target")
        let target = SpinLabDomain.RouteTarget(sampleId: "PN70", channels: ["file"])
        let service = InboxArchiveApplyService()

        _ = try service.apply(
            pending: pending,
            targets: [target],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL
        )

        let sidecar = try fixture.loadSidecar(sampleID: "PN70", category: "General", fileName: pending.fileName)
        #expect(sidecar.sampleKey == "PN70")
    }

    // MARK: - B: multi-target DAT produces sidecars with distinct correct sampleKey values

    @Test("multi-target DAT: ch1→sample4, ch2→sample5 produce distinct sidecar.sampleKey values")
    func multiTargetDATWritesDistinctSampleKeys() throws {
        let fixture = try Fixture.make(sampleIDs: ["sample4", "sample5"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(
            fileName: "RT_ch1_sample4_ch2_sample5.dat",
            contents: Fixture.ppmsDATContent
        )
        let targets = [
            SpinLabDomain.RouteTarget(sampleId: "sample4", channels: ["ch1"]),
            SpinLabDomain.RouteTarget(sampleId: "sample5", channels: ["ch2"])
        ]
        let service = InboxArchiveApplyService()

        _ = try service.apply(
            pending: pending,
            targets: targets,
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL
        )

        let sidecar4 = try fixture.loadSidecar(sampleID: "sample4", category: "General", fileName: pending.fileName)
        let sidecar5 = try fixture.loadSidecar(sampleID: "sample5", category: "General", fileName: pending.fileName)
        #expect(sidecar4.sampleKey == "sample4")
        #expect(sidecar5.sampleKey == "sample5")
        // Bonus integration check: both derive the same instrumentHeader timestamp from the shared source file.
        #expect(sidecar4.measurementTimestamp?.provenance == .instrumentHeader)
        #expect(sidecar5.measurementTimestamp?.provenance == .instrumentHeader)
        #expect(sidecar4.measurementTimestamp?.value == sidecar5.measurementTimestamp?.value)
    }

    // MARK: - F: old sidecar without the new fields still decodes

    @Test("old sidecar JSON without sampleKey/measurementTimestamp still decodes")
    func oldSidecarWithoutNewFieldsDecodes() throws {
        let legacyJSON = """
        {
            "version": 2,
            "workflow": "ahe",
            "autoDetectedWorkflow": "ahe",
            "workflowSource": "auto",
            "workflowDisplayName": "AHE",
            "channels": ["CH1"],
            "sourceFilePath": "/data/sample/meas.csv",
            "appliedAt": "2024-01-01T00:00:00Z",
            "ruleSnapshot": {
                "ruleSetVersion": 1,
                "ruleSetFingerprint": "legacy",
                "appliedAt": "2024-01-01T00:00:00Z",
                "fields": { "conditions": {}, "substrateTags": [] }
            },
            "userOverrides": { "conditions": {} }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SpinLabFileSidecar.self, from: Data(legacyJSON.utf8))

        #expect(decoded.sampleKey == nil)
        #expect(decoded.measurementTimestamp == nil)
        #expect(decoded.workflow == "ahe")
    }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    var rootURL: URL
    var libraryRootURL: URL
    var libraryStore: LibraryStore
    var libraryIndex: LibraryIndex
    var samplesByID: [String: LibrarySample]

    static let ppmsDATContent = """
    [Header]
    TITLE, default name
    FILEOPENTIME,38091212.03,3/18/2026,1:24 PM
    BYAPP, Resistivity, 2.1, 1.0
    [Data]
    Temperature (K),Bridge 1 Resistance (Ohms)
    170.0,100.0
    """

    static func make(sampleIDs: [String]) throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-testrecord-p1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let libraryRootURL = rootURL.appendingPathComponent("library", isDirectory: true)
        let libraryStore = LibraryStore()
        libraryStore.ensureRoot(at: libraryRootURL)

        let batch = LibraryBatch(
            id: "BATCH1",
            displayName: "BATCH1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: .now
        )
        var samplesByID: [String: LibrarySample] = [:]
        for sampleID in sampleIDs {
            let sample = LibrarySample(
                id: sampleID,
                displayName: sampleID,
                batchId: batch.id,
                substrateRaw: "STO(111)",
                substrateDisplay: "STO(111)",
                substrateTokens: ["STO", "111"],
                substrateTags: ["STO", "111"],
                metadata: [:],
                orderedMetadata: [],
                numericTags: [:],
                numericDisplay: [:],
                sourceSheetName: "Sheet1",
                sourceRowNumber: 1,
                updatedAt: .now
            )
            samplesByID[sampleID] = sample
            try libraryStore.createDrawer(for: sample, batch: batch, rootURL: libraryRootURL)
        }

        let libraryIndex = libraryStore.syncIndexFromFilesystem(rootURL: libraryRootURL)
        return Fixture(
            rootURL: rootURL,
            libraryRootURL: libraryRootURL,
            libraryStore: libraryStore,
            libraryIndex: libraryIndex,
            samplesByID: samplesByID
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makePending(fileName: String, contents: String) throws -> SpinLabDomain.PendingImport {
        let sourceURL = rootURL.appendingPathComponent(fileName)
        try Data(contents.utf8).write(to: sourceURL)
        return SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: sourceURL.path,
            originalFilePath: sourceURL.path,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
    }

    func destination(sampleID: String, category: String, fileName: String) -> URL {
        let sample = samplesByID[sampleID]!
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        return drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appending(path: category, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    func loadSidecar(sampleID: String, category: String, fileName: String) throws -> SpinLabFileSidecar {
        let measurementURL = destination(sampleID: sampleID, category: category, fileName: fileName)
        let sidecarURL = measurementURL.deletingPathExtension()
            .appendingPathExtension(measurementURL.pathExtension + ".spinlab.json")
        let data = try Data(contentsOf: sidecarURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SpinLabFileSidecar.self, from: data)
    }
}
