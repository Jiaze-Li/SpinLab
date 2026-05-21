import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.5.2 Library Settings Bookmark")
struct V552LibrarySettingsBookmarkTests {
    @Test("LibrarySettings encodes and decodes root bookmark data")
    func settingsRoundTripsBookmarkData() throws {
        let settings = LibrarySettings(
            rootPath: "/tmp/library-root",
            rootBookmarkData: Data([1, 2, 3, 4]),
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: ["PN"],
            lastRefreshAt: nil
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(LibrarySettings.self, from: data)

        #expect(decoded.rootPath == settings.rootPath)
        #expect(decoded.rootBookmarkData == settings.rootBookmarkData)
        #expect(decoded.allowedBatchPrefixes == ["PN"])
    }

    @Test("Missing bookmark falls back outside sandbox")
    func missingBookmarkFallsBackOutsideSandbox() {
        let settings = LibrarySettings(
            rootPath: "/tmp/library-root",
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let status = LibraryRootAccess().resolveRootURL(settings: settings, sandboxed: false)

        if case .fallback(let url) = status {
            #expect(url.path == "/tmp/library-root")
        } else {
            Issue.record("Expected fallback status")
        }
    }

    @Test("Missing bookmark is rejected in sandbox")
    func missingBookmarkRejectedInSandbox() {
        let settings = LibrarySettings(
            rootPath: "/tmp/library-root",
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let status = LibraryRootAccess().resolveRootURL(settings: settings, sandboxed: true)
        if case .missingBookmark = status {
            // expected
        } else {
            Issue.record("Expected missingBookmark status")
        }
    }

    @Test("Bookmark resolution detects stale bookmark when directory moves")
    func staleBookmarkDetectedWhenDirectoryMoves() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "spinlab-bookmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        let moved = fm.temporaryDirectory.appending(path: "spinlab-bookmark-moved-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: moved)
        }

        let bookmark = try root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        try fm.moveItem(at: root, to: moved)

        let settings = LibrarySettings(
            rootPath: moved.path,
            rootBookmarkData: bookmark,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let status = LibraryRootAccess().resolveRootURL(settings: settings, sandboxed: true)
        switch status {
        case .staleBookmark, .available:
            // platform-dependent; stale is preferred, available is acceptable if bookmark tracks rename
            break
        default:
            Issue.record("Expected staleBookmark or available status")
        }
    }
}
