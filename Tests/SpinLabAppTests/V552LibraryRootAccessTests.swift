import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.5.2 Library Root Access")
struct V552LibraryRootAccessTests {
    @Test("enumerateSidecarURLs finds measurement sidecars under the library root")
    func enumerateSidecarsFindsMeasurementFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "spinlab-root-access-\(UUID().uuidString)", directoryHint: .isDirectory)
        let measurements = root.appending(path: "batches/PN31/samples/PN31-b-STO-111/measurements", directoryHint: .isDirectory)
        try fm.createDirectory(at: measurements, withIntermediateDirectories: true)
        let sidecar = measurements.appending(path: "example.spinlab.json")
        try "{}".data(using: .utf8)!.write(to: sidecar)
        defer { try? fm.removeItem(at: root) }

        let settings = LibrarySettings(
            rootPath: root.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )
        let urls = LibraryRootAccess().enumerateSidecarURLs(settings: settings, sandboxed: false).urls

        #expect(urls.count == 1)
        #expect(urls[0].lastPathComponent == "example.spinlab.json")
    }

    @Test("enumerateSidecarURLs returns empty for a root without measurement sidecars")
    func enumerateSidecarsReturnsEmptyWhenNoFilesExist() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "spinlab-root-access-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let settings = LibrarySettings(
            rootPath: root.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )
        let urls = LibraryRootAccess().enumerateSidecarURLs(settings: settings, sandboxed: false).urls

        #expect(urls.isEmpty)
    }
}
