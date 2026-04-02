import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.6.0 Measurements Display")
struct V260MeasurementsDisplayTests {
    @Test("sample with sidecar gets applied measurements on demand")
    func sampleWithSidecarGetsAppliedMeasurements() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN90"])
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            sampleID: "PN90",
            workflowFolder: "XY",
            fileName: "pn90_xy.dat",
            sidecar: SpinLabFileSidecar(
                workflow: "XY",
                workflowDisplayName: "XY Rotation",
                conditions: ["temperature": "80K", "field": "8T"],
                channels: ["XRD"],
                sourceFilePath: "/tmp/pn90_xy.dat",
                appliedAt: Date(timeIntervalSince1970: 1_710_000_000)
            )
        )

        guard let sample = fixture.samplesByID["PN90"] else {
            Issue.record("Expected fixture sample PN90.")
            return
        }
        let measurements = fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL)
        #expect(measurements.count == 1)
        let m = measurements[0]
        #expect(m.id.hasSuffix(".spinlab.json"))
        #expect(m.workflow == "XY")
        #expect(m.conditions == ["temperature": "80K", "field": "8T"])
        #expect(m.sourceFileName == "pn90_xy.dat")
    }

    @Test("sample without sidecar keeps applied measurements empty on demand")
    func sampleWithoutSidecarHasEmptyMeasurements() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN91"])
        defer { fixture.cleanup() }

        guard let sample = fixture.samplesByID["PN91"] else {
            Issue.record("Expected fixture sample PN91.")
            return
        }
        let measurements = fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL)
        #expect(measurements.isEmpty)
    }

    @Test("fan-out sidecars across subfolders are collected and sorted by appliedAt desc")
    func fanOutSidecarsAreCollectedAndSorted() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN92"])
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            sampleID: "PN92",
            workflowFolder: "RT/ch1",
            fileName: "pn92_old.dat",
            sidecar: SpinLabFileSidecar(
                workflow: "RT",
                workflowDisplayName: "RT",
                conditions: ["current": "1mA"],
                channels: ["ch1"],
                sourceFilePath: "/tmp/pn92_old.dat",
                appliedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        try fixture.writeSidecar(
            sampleID: "PN92",
            workflowFolder: "RT/ch2",
            fileName: "pn92_new.dat",
            sidecar: SpinLabFileSidecar(
                workflow: "RT",
                workflowDisplayName: "RT",
                conditions: ["current": "2mA"],
                channels: ["ch2"],
                sourceFilePath: "/tmp/pn92_new.dat",
                appliedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        guard let sample = fixture.samplesByID["PN92"] else {
            Issue.record("Expected fixture sample PN92.")
            return
        }
        let measurements = fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL)

        #expect(measurements.count == 2)
        #expect(measurements[0].sourceFileName == "pn92_new.dat")
        #expect(measurements[1].sourceFileName == "pn92_old.dat")
    }

    @Test("invalid sidecar JSON is skipped while valid sidecars still load")
    func invalidSidecarJSONIsSkipped() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN93"])
        defer { fixture.cleanup() }

        try fixture.writeSidecar(
            sampleID: "PN93",
            workflowFolder: "AMR",
            fileName: "pn93_valid.dat",
            sidecar: SpinLabFileSidecar(
                workflow: "AMR",
                workflowDisplayName: "AMR",
                conditions: ["temperature": "300K"],
                channels: ["file"],
                sourceFilePath: "/tmp/pn93_valid.dat",
                appliedAt: Date(timeIntervalSince1970: 1_750_000_000)
            )
        )
        try fixture.writeCorruptedSidecar(
            sampleID: "PN93",
            workflowFolder: "AMR",
            fileName: "pn93_broken.dat"
        )

        guard let sample = fixture.samplesByID["PN93"] else {
            Issue.record("Expected fixture sample PN93.")
            return
        }
        let measurements = fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: fixture.libraryRootURL)

        #expect(measurements.count == 1)
        #expect(measurements[0].sourceFileName == "pn93_valid.dat")
    }

    @Test("sidecar snapshot changes after writing a new sidecar")
    func sidecarSnapshotChangesWhenFilesChange() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN95"])
        defer { fixture.cleanup() }

        guard let sample = fixture.samplesByID["PN95"] else {
            Issue.record("Expected fixture sample PN95.")
            return
        }

        let before = fixture.libraryStore.sidecarSnapshot(for: sample, rootURL: fixture.libraryRootURL)
        #expect(before == .empty)

        try fixture.writeSidecar(
            sampleID: "PN95",
            workflowFolder: "RT",
            fileName: "pn95_rt.dat",
            sidecar: SpinLabFileSidecar(
                workflow: "RT",
                workflowDisplayName: "RT",
                conditions: ["current": "1mA"],
                channels: ["file"],
                sourceFilePath: "/tmp/pn95_rt.dat",
                appliedAt: Date(timeIntervalSince1970: 1_770_000_000)
            )
        )

        let after = fixture.libraryStore.sidecarSnapshot(for: sample, rootURL: fixture.libraryRootURL)
        #expect(after.fileCount == 1)
        #expect(after != before)
    }

    @Test("backfill creates missing sidecars for measurement files")
    func backfillCreatesMissingSidecars() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN96"])
        defer { fixture.cleanup() }

        try fixture.writeMeasurementFile(
            sampleID: "PN96",
            workflowFolder: "RT",
            fileName: "pn96_rt_legacy.dat",
            contents: "legacy-data"
        )

        let rootURL = fixture.libraryRootURL
        let result = fixture.libraryStore.backfillMissingMeasurementSidecars(rootURL: rootURL)
        #expect(result.createdSidecarCount == 1)
        #expect(result.failedSidecarCount == 0)

        guard let sample = fixture.samplesByID["PN96"] else {
            Issue.record("Expected fixture sample PN96.")
            return
        }
        let measurements = fixture.libraryStore.loadAppliedMeasurements(for: sample, rootURL: rootURL)
        #expect(measurements.count == 1)
        #expect(measurements[0].workflow == "RT")
        #expect(measurements[0].sourceFileName == "pn96_rt_legacy.dat")
    }

    @Test("sample json does not include appliedMeasurements key")
    func sampleJSONDoesNotIncludeAppliedMeasurementsKey() throws {
        let fixture = try Fixture.make(sampleIDs: [])
        defer { fixture.cleanup() }

        let batch = fixture.defaultBatch
        let sample = LibrarySample(
            id: "PN94",
            displayName: "PN94",
            batchId: batch.id,
            substrateRaw: "STO(111)",
            substrateDisplay: "STO(111)",
            substrateTokens: ["STO", "111"],
            substrateTags: ["STO", "111"],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: .now,
            appliedMeasurements: [
                AppliedMeasurement(
                    id: "/tmp/fake.spinlab.json",
                    workflow: "RT",
                    workflowDisplayName: "RT",
                    conditions: ["current": "1mA"],
                    appliedAt: .now,
                    sourceFileName: "fake.dat"
                )
            ]
        )

        fixture.libraryStore.createDrawer(for: sample, batch: batch, rootURL: fixture.libraryRootURL)
        let sampleJSON = fixture.libraryStore
            .drawerRootURL(for: sample, rootURL: fixture.libraryRootURL)
            .appending(path: "sample.json", directoryHint: .notDirectory)
        let data = try Data(contentsOf: sampleJSON)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            Issue.record("sample.json should decode as an object.")
            return
        }
        #expect(json["appliedMeasurements"] == nil)
    }
}

@MainActor
private struct Fixture {
    var rootURL: URL
    var libraryRootURL: URL
    var libraryStore: LibraryStore
    var samplesByID: [String: LibrarySample]
    var defaultBatch: LibraryBatch

    static func make(sampleIDs: [String]) throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v260-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let libraryRootURL = rootURL.appendingPathComponent("library", isDirectory: true)
        let libraryStore = LibraryStore()
        libraryStore.ensureRoot(at: libraryRootURL)

        let batch = LibraryBatch(
            id: "PN",
            displayName: "PN",
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
                numericTags: [:],
                numericDisplay: [:],
                updatedAt: .now
            )
            samplesByID[sampleID] = sample
            libraryStore.createDrawer(for: sample, batch: batch, rootURL: libraryRootURL)
        }

        return Fixture(
            rootURL: rootURL,
            libraryRootURL: libraryRootURL,
            libraryStore: libraryStore,
            samplesByID: samplesByID,
            defaultBatch: batch
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeSidecar(
        sampleID: String,
        workflowFolder: String,
        fileName: String,
        sidecar: SpinLabFileSidecar
    ) throws {
        guard let sample = samplesByID[sampleID] else {
            throw NSError(domain: "Fixture", code: 1)
        }
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        let folderURL = drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appendingPathComponent(workflowFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let sidecarURL = folderURL.appendingPathComponent(fileName + ".spinlab.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: sidecarURL)
    }

    func writeCorruptedSidecar(
        sampleID: String,
        workflowFolder: String,
        fileName: String
    ) throws {
        guard let sample = samplesByID[sampleID] else {
            throw NSError(domain: "Fixture", code: 2)
        }
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        let folderURL = drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appendingPathComponent(workflowFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let sidecarURL = folderURL.appendingPathComponent(fileName + ".spinlab.json", isDirectory: false)
        try Data("{not-json".utf8).write(to: sidecarURL)
    }

    func writeMeasurementFile(
        sampleID: String,
        workflowFolder: String,
        fileName: String,
        contents: String
    ) throws {
        guard let sample = samplesByID[sampleID] else {
            throw NSError(domain: "Fixture", code: 3)
        }
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        let folderURL = drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appendingPathComponent(workflowFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: folderURL.appendingPathComponent(fileName, isDirectory: false))
    }
}
