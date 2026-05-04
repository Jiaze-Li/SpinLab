import Foundation
@testable import SpinLabApp
import Testing

struct V5115LibraryStoreCharacterizationTests {
    @Test
    func ensureRootCreatesIndexAndBatchesDirectories() throws {
        let rootURL = try temporaryRoot()
        let store = LibraryStore()

        store.ensureRoot(at: rootURL)

        #expect(FileManager.default.fileExists(atPath: rootURL.appending(path: "index").path))
        #expect(FileManager.default.fileExists(atPath: rootURL.appending(path: "batches").path))
    }

    @Test
    func verifyRootCreatesProbeDirectoryAndReturnsIt() throws {
        let rootURL = try temporaryRoot()
        let store = LibraryStore()

        let probeURL = store.verifyRoot(at: rootURL)

        #expect(probeURL == rootURL.appending(path: "__spinlab_library_root_check", directoryHint: .isDirectory))
        #expect(FileManager.default.fileExists(atPath: probeURL?.path ?? ""))
    }

    @Test
    func syncIndexFromFilesystemPersistsEmptyIndex() throws {
        let rootURL = try temporaryRoot()
        let store = LibraryStore()

        let index = store.syncIndexFromFilesystem(rootURL: rootURL)
        let persisted = store.loadIndex(from: rootURL)

        #expect(index.version == 1)
        #expect(index.batches.isEmpty)
        #expect(index.samples.isEmpty)
        #expect(persisted?.batches.isEmpty == true)
        #expect(persisted?.samples.isEmpty == true)
    }

    @Test
    func snapshotIndexFromFilesystemDoesNotPersistIndexFile() throws {
        let rootURL = try temporaryRoot()
        let store = LibraryStore()

        let index = store.snapshotIndexFromFilesystem(rootURL: rootURL)
        let indexURL = rootURL
            .appending(path: "index", directoryHint: .isDirectory)
            .appending(path: "library_index.json")

        #expect(index.batches.isEmpty)
        #expect(index.samples.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: indexURL.path))
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-v5115-librarystore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
