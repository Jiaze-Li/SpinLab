import Foundation
import Testing
@testable import SpinLabApp

/// Task 12: the confirmation-time guard on `LibraryResultService.setValue` and target resolution.
/// Extends `LibraryWriteLeaseTests` so these tests share its serialisation of the process-wide lease.
extension LibraryWriteLeaseTests {

    private struct Fixture {
        var root: URL
        var lockDir: URL
        var store: LibraryStore
        var service: LibraryResultService
        var sample: LibrarySample
        var other: LibrarySample
        var definition: ResultDefinition
        var session: String
    }

    private func t12Temp(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "spinlab-t12-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func t12Sample(_ id: String, batch: String = "PN101") -> LibrarySample {
        LibrarySample(
            id: id, displayName: id, batchId: batch,
            substrateRaw: "STO(001)", substrateDisplay: "STO(001)", substrateTokens: ["STO"],
            substrateTags: ["STO"], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:],
            updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: nil,
            legacySampleKey: nil, origin: "native", deletedAt: nil)
    }

    private func t12Bytes(_ root: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        for case let rel as String in enumerator?.allObjects ?? [] {
            if let data = FileManager.default.contents(atPath: root.appending(path: rel).path) { result[rel] = data }
        }
        return result
    }

    private func withFixture(unit: String = "mT", _ body: (Fixture) throws -> Void) throws {
        let root = try t12Temp("lib"), lockDir = try t12Temp("locks")
        let store = LibraryStore()
        let sample = t12Sample("PN101-A"), other = t12Sample("PN101-B")
        let batch = LibraryBatch(id: "PN101", displayName: "PN101", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:],
                                 sampleKeys: [sample.id, other.id], updatedAt: Date(), origin: "native")
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        try store.createDrawer(for: other, batch: batch, rootURL: root)
        let service = LibraryResultService(libraryStore: store)
        let definition = try service.createDefinition(name: "Hc", unit: unit, qualifier: "300 K", rootURL: root)
        LibraryWriteLease.shared.lockDirectory = lockDir
        defer {
            LibraryWriteLease.shared.release(); LibraryWriteLease.shared.lockDirectory = nil
            try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: lockDir)
        }
        #expect(LibraryWriteLease.shared.acquire(rootURL: root) == .writable)
        let session = try #require(LibraryWriteLease.shared.sessionID)
        try body(Fixture(root: root, lockDir: lockDir, store: store, service: service, sample: sample, other: other,
                         definition: definition, session: session))
    }

    private func t12Guard(_ f: Fixture, batch: String = "PN101") -> ResultWriteGuard {
        ResultWriteGuard(rootURL: f.root, leaseSessionID: f.session, definition: f.definition, targetBatchID: batch)
    }

    private func t12Value(_ f: Fixture, _ sample: LibrarySample) -> Double? {
        let url = f.store.drawerRootURL(for: sample, rootURL: f.root).appending(path: "sample.json")
        return f.store.decodeSample(from: url)?.results?[f.definition.definitionID]?.value
    }

    @Test("guarded write stores exactly the confirmed number on the one Sample and nothing else")
    func guardedWriteHappyPath() throws {
        try withFixture { f in
            let before = t12Bytes(f.root)
            try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 50, expectedCurrent: nil,
                                   rootURL: f.root, writeGuard: t12Guard(f))
            #expect(t12Value(f, f.sample) == 50)
            #expect(t12Value(f, f.other) == nil)
            let after = t12Bytes(f.root)
            let changed = Set(after.keys).symmetricDifference(before.keys).union(after.keys.filter { before[$0] != after[$0] })
            #expect(changed.allSatisfy { $0.hasSuffix("PN101-A/sample.json") }, "only the target sample.json changes: \(changed)")
            // Repeated confirmation (even with the same number) is refused, not written twice.
            #expect(throws: LibraryResultError.staleValue) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 50, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
        }
    }

    @Test("a value changed elsewhere after the panel opened is refused; the new value survives")
    func staleValueRefused() throws {
        try withFixture { f in
            try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 7, expectedCurrent: nil, rootURL: f.root)
            #expect(throws: LibraryResultError.staleValue) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 50, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(t12Value(f, f.sample) == 7)
        }
    }

    @Test("a Definition whose unit or qualifier changed is refused; a rename alone is fine; a deleted one is unknown")
    func definitionChanges() throws {
        try withFixture { f in
            let id = f.definition.definitionID
            _ = try f.service.updateDefinition(definitionID: id, name: "Hc renamed", unit: "mT", qualifier: "300 K", rootURL: f.root)
            try f.service.setValue(sample: f.sample, definitionID: id, newValue: 1, expectedCurrent: nil, rootURL: f.root, writeGuard: t12Guard(f))
            try f.service.setValue(sample: f.sample, definitionID: id, newValue: nil, expectedCurrent: 1, rootURL: f.root)

            _ = try f.service.updateDefinition(definitionID: id, name: "Hc", unit: "T", qualifier: "300 K", rootURL: f.root)
            #expect(throws: LibraryResultError.definitionChanged) {
                try f.service.setValue(sample: f.sample, definitionID: id, newValue: 50, expectedCurrent: nil, rootURL: f.root, writeGuard: t12Guard(f))
            }
            _ = try f.service.updateDefinition(definitionID: id, name: "Hc", unit: "mT", qualifier: "10 K", rootURL: f.root)
            #expect(throws: LibraryResultError.definitionChanged) {
                try f.service.setValue(sample: f.sample, definitionID: id, newValue: 50, expectedCurrent: nil, rootURL: f.root, writeGuard: t12Guard(f))
            }
            try f.service.deleteDefinition(definitionID: id, rootURL: f.root)
            #expect(throws: LibraryResultError.unknownDefinition(id)) {
                try f.service.setValue(sample: f.sample, definitionID: id, newValue: 50, expectedCurrent: nil, rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(t12Value(f, f.sample) == nil)
        }
    }

    @Test("a Sample moved to the Trash, or a different batch identity, is refused")
    func sampleStateRefused() throws {
        try withFixture { f in
            #expect(throws: LibraryResultError.libraryChanged("target Sample identity")) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f, batch: "PN999"))
            }
            #expect(throws: LibraryResultError.libraryChanged("target Sample identity")) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f, batch: ""))
            }
            let url = f.store.drawerRootURL(for: f.sample, rootURL: f.root).appending(path: "sample.json")
            var trashed = try #require(f.store.decodeSample(from: url))
            trashed.deletedAt = Date()
            try f.store.writeJSONChecked(trashed, to: url)
            #expect(throws: LibraryResultError.sampleInTrash) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(t12Value(f, f.sample) == nil)
        }
    }

    @Test("switching Library and coming back (A→B→A) invalidates an earlier confirmation; so does a different root")
    func sessionAndRootChanges() throws {
        try withFixture { f in
            let otherLib = try t12Temp("other")
            defer { try? FileManager.default.removeItem(at: otherLib) }
            // Different root than the one confirmed against.
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: otherLib, writeGuard: t12Guard(f))
            }
            // A → B → A.
            #expect(LibraryWriteLease.shared.acquire(rootURL: otherLib) == .writable)
            #expect(LibraryWriteLease.shared.acquire(rootURL: f.root) == .writable)
            #expect(throws: LibraryResultError.libraryChanged("the Library was reopened")) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            // Same-root reopen.
            let reopenedGuard = ResultWriteGuard(rootURL: f.root, leaseSessionID: try #require(LibraryWriteLease.shared.sessionID),
                                                 definition: f.definition, targetBatchID: "PN101")
            LibraryWriteLease.shared.acquire(rootURL: f.root)
            #expect(throws: LibraryResultError.libraryChanged("the Library was reopened")) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: reopenedGuard)
            }
            #expect(t12Value(f, f.sample) == nil)
        }
    }

    @Test("a lost or read-only lease refuses the guarded write; nothing changes on disk")
    func leaseLost() throws {
        try withFixture { f in
            let holder = LibraryWriteLease(lockDirectory: f.lockDir)
            LibraryWriteLease.shared.release()
            #expect(holder.acquire(rootURL: f.root) == .writable)
            #expect(LibraryWriteLease.shared.acquire(rootURL: f.root) != .writable)
            defer { holder.release() }
            let readOnlyGuard = ResultWriteGuard(rootURL: f.root, leaseSessionID: try #require(LibraryWriteLease.shared.sessionID),
                                                 definition: f.definition, targetBatchID: "PN101")
            let before = t12Bytes(f.root)
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: readOnlyGuard)
            }
            #expect(t12Bytes(f.root) == before)

            // No lease at all (released): guarded write is refused even though plain `ensureWritable` would pass.
            LibraryWriteLease.shared.release()
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(t12Bytes(f.root) == before)
        }
    }

    @Test("a Library that has become V2, or whose layout is unreadable, is refused and not written")
    func layoutChanged() throws {
        try withFixture { f in
            let before = t12Bytes(f.root)
            let marker = f.root.appending(path: "_spinlab/layout_version.json")
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"version\": 2}".utf8).write(to: marker)
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(throws: LibraryResultError.self) {
                _ = try f.service.resolveV1AssignmentTarget(batchID: "PN101", sampleKey: f.sample.id, rootURL: f.root)
            }
            try Data("{not json".utf8).write(to: marker)
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            try FileManager.default.removeItem(at: marker)
            // Nothing but our own marker file changed.
            let sampleURL = f.store.drawerRootURL(for: f.sample, rootURL: f.root).appending(path: "sample.json")
            #expect(FileManager.default.contents(atPath: sampleURL.path) == before.first { $0.key.hasSuffix("PN101-A/sample.json") }?.value)
        }
    }

    @Test("corrupt Catalog or sample.json is refused and the disk is untouched")
    func corruptFiles() throws {
        try withFixture { f in
            let sampleURL = f.store.drawerRootURL(for: f.sample, rootURL: f.root).appending(path: "sample.json")
            let good = try Data(contentsOf: sampleURL)
            try Data("{corrupt".utf8).write(to: sampleURL)
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(try Data(contentsOf: sampleURL) == Data("{corrupt".utf8))
            try good.write(to: sampleURL)

            let catalogURL = f.service.catalogURL(f.root)
            let goodCatalog = try Data(contentsOf: catalogURL)
            try Data("{corrupt".utf8).write(to: catalogURL)
            #expect(throws: LibraryResultError.self) {
                try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 5, expectedCurrent: nil,
                                       rootURL: f.root, writeGuard: t12Guard(f))
            }
            #expect(try Data(contentsOf: catalogURL) == Data("{corrupt".utf8))
            try goodCatalog.write(to: catalogURL)
            #expect(t12Value(f, f.sample) == nil)
        }
    }

    @Test("non-finite numbers are refused before anything is read or written")
    func nonFiniteRefused() throws {
        try withFixture { f in
            for bad in [Double.nan, .infinity, -.infinity] {
                #expect(throws: LibraryResultError.invalidValue) {
                    try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: bad, expectedCurrent: nil,
                                           rootURL: f.root, writeGuard: t12Guard(f))
                }
            }
        }
    }

    @Test("target resolution reads the formal V1 record; missing, mismatched, ambiguous and Trash samples are refused")
    func targetResolution() throws {
        try withFixture { f in
            let resolved = try f.service.resolveV1AssignmentTarget(batchID: "PN101", sampleKey: f.sample.id, rootURL: f.root)
            #expect(resolved.id == f.sample.id && resolved.batchId == "PN101")
            // Batch unknown: unique by id.
            #expect(try f.service.resolveV1AssignmentTarget(batchID: "", sampleKey: f.other.id, rootURL: f.root).id == f.other.id)
            // Missing / wrong batch.
            #expect(throws: LibraryResultError.self) { _ = try f.service.resolveV1AssignmentTarget(batchID: "PN101", sampleKey: "NOPE", rootURL: f.root) }
            #expect(throws: LibraryResultError.self) { _ = try f.service.resolveV1AssignmentTarget(batchID: "PN555", sampleKey: f.sample.id, rootURL: f.root) }
            #expect(throws: LibraryResultError.self) { _ = try f.service.resolveV1AssignmentTarget(batchID: "", sampleKey: "NOPE", rootURL: f.root) }
            // Same id in a second batch: ambiguous without a batch, still exact with one.
            let dup = t12Sample("PN101-A", batch: "PN202")
            let batch2 = LibraryBatch(id: "PN202", displayName: "PN202", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:],
                                      sampleKeys: [dup.id], updatedAt: Date(), origin: "native")
            try f.store.createDrawer(for: dup, batch: batch2, rootURL: f.root)
            #expect(throws: LibraryResultError.self) { _ = try f.service.resolveV1AssignmentTarget(batchID: "", sampleKey: "PN101-A", rootURL: f.root) }
            #expect(try f.service.resolveV1AssignmentTarget(batchID: "PN202", sampleKey: "PN101-A", rootURL: f.root).batchId == "PN202")
            // Trash.
            let url = f.store.drawerRootURL(for: f.other, rootURL: f.root).appending(path: "sample.json")
            var trashed = try #require(f.store.decodeSample(from: url)); trashed.deletedAt = Date()
            try f.store.writeJSONChecked(trashed, to: url)
            #expect(throws: LibraryResultError.sampleInTrash) { _ = try f.service.resolveV1AssignmentTarget(batchID: "PN101", sampleKey: f.other.id, rootURL: f.root) }
        }
    }

    @Test("manual entry without a guard behaves as before; zero is a real value")
    func manualPathUnchanged() throws {
        try withFixture { f in
            try f.service.setValue(sample: f.sample, definitionID: f.definition.definitionID, newValue: 0, expectedCurrent: nil, rootURL: f.root)
            #expect(t12Value(f, f.sample) == 0, "zero is a real value")
            #expect(try f.service.currentValueOnDisk(sample: f.sample, definitionID: f.definition.definitionID, rootURL: f.root) == 0)
        }
    }
}
