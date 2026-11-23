import Foundation
import Testing
@testable import SpinLabApp

/// Task 3: one local SpinLab process may write to a given Library; a second one is read-only.
/// Serialized because the guard reads the process-wide `LibraryWriteLease.shared`.
@Suite("Library single-writer lease", .serialized)
struct LibraryWriteLeaseTests {
    private func makeTemp(_ name: String = "lease") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    /// A separate lease object stands in for "another SpinLab process": flock conflicts across
    /// distinct open file descriptions even inside one process.
    private func otherInstance(_ lockDir: URL) -> LibraryWriteLease { LibraryWriteLease(lockDirectory: lockDir) }

    /// Relative path + content of everything under `root`.
    private func snapshot(_ root: URL) -> [String] {
        let e = FileManager.default.enumerator(atPath: root.path)
        return (e?.allObjects as? [String] ?? []).sorted().map { rel in
            let data = FileManager.default.contents(atPath: root.appending(path: rel).path)
            return "\(rel):\(data?.hashValue ?? 0)"
        }
    }

    private func makeSample(deletedAt: Date? = nil) -> LibrarySample {
        LibrarySample(
            id: "PN101-STO-001", displayName: "PN101-STO-001", batchId: "PN101",
            substrateRaw: "STO(001)", substrateDisplay: "STO(001)", substrateTokens: ["STO", "001"],
            substrateTags: ["STO"], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:],
            updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: UUID().uuidString,
            legacySampleKey: nil, origin: "native", deletedAt: deletedAt)
    }

    private func seedLibrary(_ lib: URL, trashed: Bool) throws {
        let store = LibraryStore()
        let sample = makeSample(deletedAt: trashed ? Date() : nil)
        let batch = LibraryBatch(id: "PN101", displayName: "PN101", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: [sample.id], updatedAt: Date(), origin: "native")
        try store.createDrawer(for: sample, batch: batch, rootURL: lib)
    }

    @Test("first instance is writable, second on same Library is read-only")
    func secondInstanceReadOnly() throws {
        let lockDir = try makeTemp("locks"); let lib = try makeTemp("lib")
        defer { try? FileManager.default.removeItem(at: lockDir); try? FileManager.default.removeItem(at: lib) }
        let first = otherInstance(lockDir), second = otherInstance(lockDir)
        #expect(first.acquire(rootURL: lib) == .writable)
        #expect(second.acquire(rootURL: lib) == .readOnly(reason: LibraryWriteLease.readOnlyMessage))
        #expect(second.isReadOnly)
        #expect(throws: AppError.self) { try second.ensureWritable(lib.appending(path: "batches/x.json")) }
        #expect(throws: Never.self) { try first.ensureWritable(lib.appending(path: "batches/x.json")) }
        // Paths outside the Library are never blocked.
        #expect(throws: Never.self) { try second.ensureWritable(lockDir.appending(path: "other.txt")) }
    }

    @Test("symlink alias contends for the same lease")
    func symlinkAlias() throws {
        let lockDir = try makeTemp("locks"); let lib = try makeTemp("lib"); let aliasDir = try makeTemp("alias")
        defer { [lockDir, lib, aliasDir].forEach { try? FileManager.default.removeItem(at: $0) } }
        let alias = aliasDir.appending(path: "LibraryAlias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: lib)
        let first = otherInstance(lockDir), second = otherInstance(lockDir)
        #expect(first.acquire(rootURL: lib) == .writable)
        #expect(second.acquire(rootURL: alias).isReadOnlyState)
        // A write addressed through the alias is refused too.
        #expect(throws: AppError.self) { try second.ensureWritable(alias.appending(path: "batches/a.json")) }
    }

    @Test("switching Library releases the old lease and evaluates the new root")
    func switchLibrary() throws {
        let lockDir = try makeTemp("locks"); let libA = try makeTemp("libA"); let libB = try makeTemp("libB")
        defer { [lockDir, libA, libB].forEach { try? FileManager.default.removeItem(at: $0) } }
        let me = otherInstance(lockDir), other = otherInstance(lockDir)
        #expect(me.acquire(rootURL: libA) == .writable)
        #expect(other.acquire(rootURL: libA).isReadOnlyState)
        #expect(me.acquire(rootURL: libB) == .writable)          // A released, B taken
        #expect(other.acquire(rootURL: libA) == .writable)       // A now free
        let third = otherInstance(lockDir)
        #expect(third.acquire(rootURL: libB).isReadOnlyState)    // B is held by me
    }

    @Test("different Libraries do not block each other")
    func independentLibraries() throws {
        let lockDir = try makeTemp("locks"); let libA = try makeTemp("libA"); let libB = try makeTemp("libB")
        defer { [lockDir, libA, libB].forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(otherInstance(lockDir).acquire(rootURL: libA) == .writable)
        let b = otherInstance(lockDir)
        #expect(b.acquire(rootURL: libB) == .writable)
    }

    @Test("lease is released when the holder process is killed")
    func releasedOnForcedTermination() throws {
        let lockDir = try makeTemp("locks"); let lib = try makeTemp("lib")
        defer { try? FileManager.default.removeItem(at: lockDir); try? FileManager.default.removeItem(at: lib) }
        // Child process takes the lease via the same lock-file scheme, then is SIGKILLed.
        let probe = otherInstance(lockDir)
        _ = probe.acquire(rootURL: lib)                 // creates the lock file
        let lockFile = try #require(try FileManager.default.contentsOfDirectory(atPath: lockDir.path).first { $0.hasSuffix(".lock") })
        probe.release()
        let path = lockDir.appending(path: lockFile).path
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-MFcntl=:flock", "-e", "open(F,'+<',$ARGV[0])||die; flock(F,LOCK_EX|LOCK_NB)||die; print \"held\\n\"; $|=1; sleep 60;", path]
        let pipe = Pipe(); child.standardOutput = pipe
        try child.run()
        _ = pipe.fileHandleForReading.availableData       // wait until "held"
        let contender = otherInstance(lockDir)
        #expect(contender.acquire(rootURL: lib).isReadOnlyState)
        kill(child.processIdentifier, SIGKILL); child.waitUntilExit()
        #expect(contender.acquire(rootURL: lib) == .writable)
    }

    // MARK: - Write boundaries refuse when read-only (shared lease)

    private func withReadOnlyLibrary(seed: (URL) throws -> Void = { _ in }, _ body: (URL) throws -> Void) throws {
        let lib = try makeTemp("ro-lib")
        try seed(lib)
        let lockDir = try makeTemp("ro-locks")
        let holder = otherInstance(lockDir)
        LibraryWriteLease.shared.lockDirectory = lockDir
        defer {
            LibraryWriteLease.shared.release(); holder.release()
            LibraryWriteLease.shared.lockDirectory = nil
            try? FileManager.default.removeItem(at: lib); try? FileManager.default.removeItem(at: lockDir)
        }
        #expect(holder.acquire(rootURL: lib) == .writable)
        #expect(LibraryWriteLease.shared.acquire(rootURL: lib).isReadOnlyState)
        try body(lib)
    }

    @Test("Result Definition and Sample Result writes are refused in a read-only Library")
    func resultWritesRefusedReadOnly() throws {
        var captured: (LibrarySample, String)?
        try withReadOnlyLibrary(seed: { lib in
            try seedLibrary(lib, trashed: false)
            let service = LibraryResultService(libraryStore: LibraryStore())
            let def = try service.createDefinition(name: "Rxx", unit: "Ω", qualifier: "", rootURL: lib)
            captured = (makeSample(), def.definitionID)
        }) { lib in
            let service = LibraryResultService(libraryStore: LibraryStore())
            let before = snapshot(lib)
            let (sample, definitionID) = try #require(captured)
            #expect(throws: AppError.self) { try service.createDefinition(name: "Z", unit: "", qualifier: "", rootURL: lib) }
            #expect(throws: AppError.self) { try service.setValue(sample: sample, definitionID: definitionID, newValue: 1, expectedCurrent: nil, rootURL: lib) }
            #expect(throws: AppError.self) { try service.deleteDefinition(definitionID: definitionID, rootURL: lib) }
            #expect(snapshot(lib) == before)
        }
    }

    @Test("read-only open creates nothing in the Library and ensureRoot is a no-op")
    func readOnlyOpenWritesNothing() throws {
        try withReadOnlyLibrary { lib in
            let before = snapshot(lib)
            let store = LibraryStore()
            store.ensureRoot(at: lib)
            #expect(throws: AppError.self) { try store.ensureRootDirectories(at: lib) }
            #expect(store.verifyRoot(at: lib) == nil)
            #expect(store.saveIndex(LibraryIndex(version: 1, createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil, metadataColumnOrder: [], batches: [], samples: []), to: lib) == false)
            #expect(snapshot(lib) == before)
        }
    }

    @Test("sample creation is rejected and changes nothing")
    func sampleCreationRejected() throws {
        try withReadOnlyLibrary { lib in
            let before = snapshot(lib)
            let outcome = NativeSampleCreationService().createSample(
                draft: CreateNativeSampleDraft(batchId: "PN110", substrateDescription: "STO(001)", displayName: "PN110 STO #1", metadata: [:]),
                rootURL: lib, libraryStore: LibraryStore(), settings: .default)
            guard case .failure = outcome else { Issue.record("expected rejection, got \(outcome)"); return }
            #expect(snapshot(lib) == before)
        }
    }

    @Test("atomic writer, write transaction, JSON writers, sync backup and disk cleanup refuse")
    func lowLevelWritersRefuse() throws {
        try withReadOnlyLibrary { lib in
            let target = lib.appending(path: "samples/S1/measurements/data.json")
            #expect(throws: AppError.self) { try AtomicFileWriter().write(Data("x".utf8), to: target) }

            let src = try makeTemp("src").appending(path: "a.txt")
            try Data("a".utf8).write(to: src)
            var tx = LibraryWriteTransaction()
            #expect(throws: AppError.self) { try tx.prepare(sourceURL: src, destinationURL: lib.appending(path: "inbox/a.txt")) }

            let store = LibraryStore()
            store.writeJSON(["k": "v"], to: lib.appending(path: "x.json"))
            #expect(throws: AppError.self) { try store.writeJSONChecked(["k": "v"], to: lib.appending(path: "y.json")) }
            let backup = try makeTemp("backup")
            #expect(store.syncBackup(from: lib, to: backup) == false)
            #expect(LibraryDiskCleanupService.deleteMetricRecordOnDisk(identityKey: "k", sampleKey: "S1", rootURL: lib) == false)
            #expect(snapshot(lib).isEmpty)
        }
    }

    @Test("Registry workbook outside the Library is refused too")
    func registryOutsideLibraryRefused() throws {
        try withReadOnlyLibrary { _ in
            let outside = try makeTemp("registry").appending(path: "Registry.xlsx")
            #expect(throws: AppError.self) {
                _ = try XLSXWorkbookKit.commitTransaction(workDir: FileManager.default.temporaryDirectory, sourceURL: outside) { _ in }
            }
            #expect(throws: AppError.self) { try LibraryWriteLease.shared.ensureLibraryWritable() }
        }
    }

    @Test("sample edit, trash, restore, permanent delete and measurement-set save are rejected")
    func sampleMutationsRejected() throws {
        try withReadOnlyLibrary(seed: { try seedLibrary($0, trashed: true) }) { lib in
            let before = snapshot(lib)
            let store = LibraryStore()
            let sample = makeSample(deletedAt: Date())
            #expect(throws: AppError.self) { try store.updateSample(sample, rootURL: lib) }
            #expect(throws: AppError.self) { _ = try store.moveSampleToTrash(sample: sample, rootURL: lib) }
            #expect(throws: AppError.self) { _ = try store.restoreSampleFromTrash(sample: sample, rootURL: lib) }
            #expect(throws: AppError.self) { try store.permanentlyDeleteTrashedSample(sample: sample, rootURL: lib) }
            #expect(throws: AppError.self) { try store.saveMeasurementSets([], for: sample, rootURL: lib) }
            #expect(snapshot(lib) == before)
        }
    }
}

private extension LibraryWriteLease.State {
    var isReadOnlyState: Bool { if case .readOnly = self { return true }; return false }
}
