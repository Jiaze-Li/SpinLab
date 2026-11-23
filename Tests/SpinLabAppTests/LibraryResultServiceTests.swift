import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpinLabApp

/// Task 4: Library Result Definitions + per-Sample current Result values.
@Suite("Task 4 Library Result Definitions and Sample values", .serialized)
struct LibraryResultServiceTests {
    private func makeTemp(_ name: String = "result") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func makeSample(id: String = "PN101-STO-001", sampleUID: String? = UUID().uuidString) -> LibrarySample {
        LibrarySample(
            id: id, displayName: id, batchId: "PN101",
            substrateRaw: "STO(001)", substrateDisplay: "STO(001)", substrateTokens: ["STO"],
            substrateTags: ["STO"], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:],
            updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: sampleUID,
            legacySampleKey: nil, origin: "native", deletedAt: nil)
    }

    private func seed(_ root: URL, sampleIDs: [String] = ["PN101-STO-001"], uid: Bool = true) throws -> (LibraryStore, [LibrarySample]) {
        let store = LibraryStore()
        let samples = sampleIDs.map { makeSample(id: $0, sampleUID: uid ? UUID().uuidString : nil) }
        let batch = LibraryBatch(id: "PN101", displayName: "PN101", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: sampleIDs, updatedAt: Date(), origin: "native")
        for sample in samples { try store.createDrawer(for: sample, batch: batch, rootURL: root) }
        return (store, samples)
    }

    private func sampleJSON(_ store: LibraryStore, _ root: URL, _ sample: LibrarySample) throws -> String {
        let url = store.sampleDirectoryURL(root, batchID: sample.batchId, sampleKey: sample.id).appending(path: "sample.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("catalog: missing is empty, create persists, 0 and empty are distinct, nothing written to Samples")
    func catalogAndValues() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root, sampleIDs: ["PN101-A", "PN101-B"])
        let service = LibraryResultService(libraryStore: store)
        #expect(service.loadCatalog(rootURL: root) == .missing)

        let rxx = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "300 K", rootURL: root)
        let alpha = try service.createDefinition(name: "alpha", unit: "", qualifier: "30° device", rootURL: root)
        #expect(rxx.definitionID.hasPrefix("rdef_"))
        guard case let .ok(catalog) = service.loadCatalog(rootURL: root) else { Issue.record("catalog"); return }
        #expect(catalog.definitions.count == 2)

        // Creating Definitions never touches Sample files.
        #expect(try sampleJSON(store, root, samples[0]).contains("\"results\"") == false)

        try service.setValue(sample: samples[0], definitionID: rxx.definitionID, newValue: 520, expectedCurrent: nil, rootURL: root)
        try service.setValue(sample: samples[1], definitionID: rxx.definitionID, newValue: 505, expectedCurrent: nil, rootURL: root)
        try service.setValue(sample: samples[0], definitionID: alpha.definitionID, newValue: 0, expectedCurrent: nil, rootURL: root)

        let diskA = store.decodeSample(from: store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: "PN101-A").appending(path: "sample.json"))
        let diskB = store.decodeSample(from: store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: "PN101-B").appending(path: "sample.json"))
        #expect(diskA?.results?[rxx.definitionID]?.value == 520)
        #expect(diskA?.results?[alpha.definitionID]?.value == 0)   // 0 is a real value
        #expect(diskB?.results?[rxx.definitionID]?.value == 505)
        #expect(diskB?.results?[alpha.definitionID] == nil)        // empty stays empty

        // Overwrite requires the value the user saw.
        #expect(throws: LibraryResultError.staleValue) {
            try service.setValue(sample: samples[0], definitionID: rxx.definitionID, newValue: 500, expectedCurrent: 999, rootURL: root)
        }
        try service.setValue(sample: samples[0], definitionID: rxx.definitionID, newValue: 500, expectedCurrent: 520, rootURL: root)
        // Clearing A leaves B and the catalog alone.
        try service.setValue(sample: samples[0], definitionID: rxx.definitionID, newValue: nil, expectedCurrent: 500, rootURL: root)
        let afterClear = store.decodeSample(from: store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: "PN101-B").appending(path: "sample.json"))
        #expect(afterClear?.results?[rxx.definitionID]?.value == 505)
        guard case let .ok(after) = service.loadCatalog(rootURL: root) else { Issue.record("catalog"); return }
        #expect(after.definitions.count == 2)
    }

    @Test("invalid values and unknown definitions are rejected")
    func invalidInput() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root)
        let service = LibraryResultService(libraryStore: store)
        let def = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "", rootURL: root)
        #expect(throws: LibraryResultError.invalidValue) {
            try service.setValue(sample: samples[0], definitionID: def.definitionID, newValue: .nan, expectedCurrent: nil, rootURL: root)
        }
        #expect(throws: LibraryResultError.invalidValue) {
            try service.setValue(sample: samples[0], definitionID: def.definitionID, newValue: .infinity, expectedCurrent: nil, rootURL: root)
        }
        #expect(throws: LibraryResultError.unknownDefinition("rdef_missing")) {
            try service.setValue(sample: samples[0], definitionID: "rdef_missing", newValue: 1, expectedCurrent: nil, rootURL: root)
        }
        #expect(throws: LibraryResultError.self) {
            try service.createDefinition(name: "  ", unit: "", qualifier: "", rootURL: root)
        }
    }

    @Test("similar definitions are flagged unless the user insists")
    func similarDefinition() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = try seed(root)
        let service = LibraryResultService(libraryStore: store)
        try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "300 K", rootURL: root)
        #expect(throws: LibraryResultError.self) {
            try service.createDefinition(name: "rxx", unit: "Ω", qualifier: "300K", rootURL: root)
        }
        try service.createDefinition(name: "rxx", unit: "Ω", qualifier: "300K", allowSimilar: true, rootURL: root)
        guard case let .ok(catalog) = service.loadCatalog(rootURL: root) else { Issue.record("catalog"); return }
        #expect(catalog.definitions.count == 2)
    }

    @Test("used definitions: unit/qualifier change needs confirmation, delete refused; unused can change and delete")
    func usedDefinitionProtection() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root)
        let service = LibraryResultService(libraryStore: store)
        let used = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "300 K", rootURL: root)
        let unused = try service.createDefinition(name: "Rzz", unit: "Ω", qualifier: "", rootURL: root)
        try service.setValue(sample: samples[0], definitionID: used.definitionID, newValue: 520, expectedCurrent: nil, rootURL: root)

        #expect(throws: LibraryResultError.changeNeedsConfirmation(affectedSamples: 1)) {
            try service.updateDefinition(definitionID: used.definitionID, name: "Rxx", unit: "Ω", qualifier: "30 K", rootURL: root)
        }
        // Renaming only is fine; confirmed meaning change is allowed and does not touch the value.
        try service.updateDefinition(definitionID: used.definitionID, name: "Rxx2", unit: "Ω", qualifier: "300 K", rootURL: root)
        try service.updateDefinition(definitionID: used.definitionID, name: "Rxx2", unit: "kΩ", qualifier: "300 K", confirmedMeaningChange: true, rootURL: root)
        let disk = store.decodeSample(from: store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: samples[0].id).appending(path: "sample.json"))
        #expect(disk?.results?[used.definitionID]?.value == 520)

        #expect(throws: LibraryResultError.definitionInUse(count: 1)) {
            try service.deleteDefinition(definitionID: used.definitionID, rootURL: root)
        }
        try service.updateDefinition(definitionID: unused.definitionID, name: "Rzz", unit: "mΩ", qualifier: "x", rootURL: root)
        try service.deleteDefinition(definitionID: unused.definitionID, rootURL: root)
        guard case let .ok(catalog) = service.loadCatalog(rootURL: root) else { Issue.record("catalog"); return }
        #expect(catalog.definitions.map(\.definitionID) == [used.definitionID])
    }

    @Test("corrupt catalog fails closed and is not overwritten")
    func corruptCatalog() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root)
        let service = LibraryResultService(libraryStore: store)
        let url = service.catalogURL(root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        guard case .unreadable = service.loadCatalog(rootURL: root) else { Issue.record("expected unreadable"); return }
        #expect(throws: LibraryResultError.self) { try service.createDefinition(name: "Rxx", unit: "", qualifier: "", rootURL: root) }
        #expect(throws: LibraryResultError.self) { try service.setValue(sample: samples[0], definitionID: "x", newValue: 1, expectedCurrent: nil, rootURL: root) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ not json")
    }

    @Test("results survive Registry-style updateSample, Sample edits, old UID-less samples and decode of old sample.json")
    func resultsPreserved() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root, uid: false)   // legacy-style Sample without sampleUID
        let service = LibraryResultService(libraryStore: store)
        let def = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "", rootURL: root)
        try service.setValue(sample: samples[0], definitionID: def.definitionID, newValue: 520, expectedCurrent: nil, rootURL: root)

        // A stale in-memory copy (no results) pushed through updateSample must not erase or revert them.
        var stale = samples[0]
        stale.metadata = ["Note": "edited"]
        stale.results = [def.definitionID: SampleResultValue(value: 1, updatedAt: Date())]
        try store.updateSample(stale, rootURL: root, changeSource: "manual_edit")
        var registryLike = samples[0]
        registryLike.results = nil
        try store.updateSample(registryLike, rootURL: root, changeSource: "registry_apply")
        // Re-applying a Registry sample over the drawer also keeps them.
        let batch = LibraryBatch(id: "PN101", displayName: "PN101", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: [samples[0].id], updatedAt: Date(), origin: "native")
        var recreated = samples[0]; recreated.origin = nil
        _ = try? store.createDrawer(for: recreated, batch: batch, rootURL: root)

        let disk = store.decodeSample(from: store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: samples[0].id).appending(path: "sample.json"))
        #expect(disk?.results?[def.definitionID]?.value == 520)
        #expect(disk?.sampleUID == nil)

        // Old sample.json without `results` still decodes.
        let json = """
        {"id":"A","displayName":"A","batchId":"B","substrateRaw":"S","substrateDisplay":"S","updatedAt":"2026-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(LibrarySample.self, from: Data(json.utf8)).results == nil)
    }

    @Test("Result values make a Sample non-empty; Definitions alone do not")
    func emptyCheck() throws {
        let root = try makeTemp(); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root)
        let service = LibraryResultService(libraryStore: store)
        let checker = LibrarySampleEmptyCheck()
        let def = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "", rootURL: root)
        #expect(checker.evaluate(sample: samples[0], rootURL: root, libraryStore: store) == .empty)
        try service.setValue(sample: samples[0], definitionID: def.definitionID, newValue: 0, expectedCurrent: nil, rootURL: root)
        let result = checker.evaluate(sample: samples[0], rootURL: root, libraryStore: store)
        guard case let .nonEmpty(reasons) = result else { Issue.record("expected nonEmpty, got \(result)"); return }
        #expect(reasons.contains("Has Sample Result values"))
    }

    @Test("Sample Detail Header, SampleResultsSection, and ResultDefinitionManagerView child controls stay within 264pt inner inspector width")
    @MainActor
    func sampleDetailAndResultViewsFit264ptInnerWidth() async throws {
        let targetWidth: CGFloat = 264

        let headerHost = ControlsSurfaceHost(width: targetWidth) {
            LibrarySampleDetailHeaderView(
                isEditingSelectedSample: false,
                sampleEditIsDirty: false,
                sampleEditIsSaving: false,
                canEditSelectedLibrarySample: true,
                sampleEditError: nil,
                sampleEditMessage: "Sample edits saved.",
                onLoadGlobalManualLogs: {},
                onLoadMetadataSyncLogs: {},
                onCancelEdit: {},
                onSaveEdit: {},
                onBeginEdit: {},
                onDelete: {}
            )
            .coordinateSpace(name: WorkbenchControlMetrics.coordinateSpaceName)
        }
        let headerIDs = [
            "library.detailHeader.title",
            "library.detailHeader.delete",
            "library.detailHeader.edit",
            "library.detailHeader.numericLog",
            "library.detailHeader.metadataLog"
        ]
        for id in headerIDs {
            let frame = try #require(headerHost.probe.frames[id], "Missing probed frame for \(id)")
            #expect(frame.minX >= -0.5 && frame.maxX <= targetWidth + 0.5, "\(id) frame \(frame) overflows 264pt")
            #expect(frame.width > 0 && frame.height > 0, "\(id) frame \(frame) has zero size")
        }

        let root = try makeTemp("ui-264"); defer { try? FileManager.default.removeItem(at: root) }
        let (store, samples) = try seed(root)
        let service = LibraryResultService(libraryStore: store)
        let defShort = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "300 K", rootURL: root)
        let defLong = try service.createDefinition(
            name: "Anomalous Hall Resistance",
            unit: "mΩ·cm",
            qualifier: "2 K, 9 T sweep, Hall bar device #3",
            rootURL: root
        )
        let updatedSample = try service.setValue(
            sample: samples[0],
            definitionID: defShort.definitionID,
            newValue: 520.125,
            expectedCurrent: nil,
            rootURL: root
        )
        _ = try service.setValue(
            sample: updatedSample,
            definitionID: defLong.definitionID,
            newValue: -12.3456,
            expectedCurrent: nil,
            rootURL: root
        )
        let finalSample = store.decodeSample(
            from: store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: samples[0].id).appending(path: "sample.json")
        ) ?? updatedSample

        let registry = WorkflowRegistry.shared
        let appState = SpinLabAppState(
            workflowBundle: registry.defaultBundle(),
            persistence: LocalJSONPersistence(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root)
        )
        appState.library.librarySettings.rootPath = root.path

        let resultsHost = ControlsSurfaceHost(width: targetWidth) {
            SampleResultsSection(sample: finalSample)
                .environment(appState)
                .coordinateSpace(name: WorkbenchControlMetrics.coordinateSpaceName)
        }
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(15))
        }
        resultsHost.resize(to: targetWidth)
        for def in [defShort, defLong] {
            for suffix in ["label", "value", "input", "confirm", "clear"] {
                let id = "library.sampleResults.\(def.definitionID).\(suffix)"
                let frame = try #require(resultsHost.probe.frames[id], "Missing probed frame for \(id)")
                #expect(frame.minX >= -0.5 && frame.maxX <= targetWidth + 0.5, "\(id) frame \(frame) overflows 264pt")
                #expect(frame.width > 0 && frame.height > 0, "\(id) frame \(frame) has zero size")
            }
            // Verify long label wraps vertically instead of pushing the value off the right edge.
            if def.definitionID == defLong.definitionID {
                let labelFrame = resultsHost.probe.frames["library.sampleResults.\(def.definitionID).label"]!
                let inputFrame = resultsHost.probe.frames["library.sampleResults.\(def.definitionID).input"]!
                #expect(inputFrame.minY >= labelFrame.maxY - 1, "Input row must sit below the label row")
                #expect(inputFrame.width >= 79.5, "Input field must retain its >=80pt usable width at 264pt")
            }
        }

        let managerHost = ControlsSurfaceHost(width: targetWidth) {
            ResultDefinitionManagerView()
                .environment(appState)
                .coordinateSpace(name: WorkbenchControlMetrics.coordinateSpaceName)
        }
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(15))
        }
        managerHost.resize(to: targetWidth)
        let managerIDs = [
            "library.resultManager.create.name",
            "library.resultManager.create.unit",
            "library.resultManager.create.qualifier",
            "library.resultManager.create.add",
            "library.resultManager.row.\(defShort.definitionID).label",
            "library.resultManager.row.\(defShort.definitionID).usage",
            "library.resultManager.row.\(defShort.definitionID).edit",
            "library.resultManager.row.\(defShort.definitionID).delete",
            "library.resultManager.row.\(defLong.definitionID).label",
            "library.resultManager.row.\(defLong.definitionID).usage",
            "library.resultManager.row.\(defLong.definitionID).edit",
            "library.resultManager.row.\(defLong.definitionID).delete"
        ]
        for id in managerIDs {
            let frame = try #require(managerHost.probe.frames[id], "Missing probed frame for \(id)")
            #expect(frame.minX >= -0.5 && frame.maxX <= targetWidth + 0.5, "\(id) frame \(frame) overflows 264pt")
            #expect(frame.width > 0 && frame.height > 0, "\(id) frame \(frame) has zero size")
        }
    }
}
