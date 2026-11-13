import Foundation
import Testing
@testable import SpinLabApp

@Suite("Native samples: symlinked Library Root")
struct NativeRootSymlinkTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-native-symlink-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Creation works when the Library Root itself is a symlink")
    func symlinkedRootAllowsCreation() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appending(path: "real", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appending(path: "link", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let store = LibraryStore()
        try store.ensureRootDirectories(at: link)
        let outcome = NativeSampleCreationService().createSample(
            draft: CreateNativeSampleDraft(batchId: "SYM1", substrateDescription: "STO(001)"),
            rootURL: link, libraryStore: store, settings: .default
        )
        guard case .success = outcome else {
            Issue.record("Creation under a symlinked root should succeed, got \(outcome)")
            return
        }
    }

    @Test("A symlink below the root or one escaping it is still rejected")
    func linksBelowOrEscapingRootAreRejected() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "root", directoryHint: .isDirectory)
        let outside = base.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let escape = root.appending(path: "escape", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)

        let store = LibraryStore()
        #expect(store.containsSymbolicLink(escape, relativeTo: root))
        #expect(store.containsSymbolicLink(escape.appending(path: "child"), relativeTo: root))
        #expect(!store.containsSymbolicLink(root.appending(path: "plain"), relativeTo: root))
    }
}
