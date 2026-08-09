import Testing
import Foundation
@testable import SpinLabApp

// PR #148 corrective pass: SearchWorkflowMeasurementsUseCase must keep security-scoped Library
// access active for the entire bulk sidecar enumeration + decode, not just the initial root
// resolution. These tests use an injectable fake LibraryRootAccessCapability to prove the bulk
// read happens inside the scoped-access callback.

private final class FakeRootAccess: LibraryRootAccessCapability {
    private(set) var withAccessCallCount = 0
    private(set) var currentDepth = 0
    var stubbedStatus: LibraryRootAccessStatus?

    func resolveRootURL(settings: LibrarySettings, sandboxed: Bool) -> LibraryRootAccessStatus {
        stubbedStatus ?? .available(rootURL: URL(fileURLWithPath: settings.rootPath ?? "", isDirectory: true))
    }

    func withAccess<T>(settings: LibrarySettings, sandboxed: Bool, _ body: (URL) throws -> T) rethrows -> T {
        withAccessCallCount += 1
        currentDepth += 1
        defer { currentDepth -= 1 }
        let rootURL = URL(fileURLWithPath: settings.rootPath ?? "", isDirectory: true)
        return try body(rootURL)
    }
}

private final class FakeSidecarBulkReader: LibrarySidecarBulkReaderCapability {
    private let onEnumerate: () -> Void

    init(onEnumerate: @escaping () -> Void) {
        self.onEnumerate = onEnumerate
    }

    func enumerateSidecars(rootURL: URL, fileManager: FileManager) -> SidecarBulkReadResult {
        onEnumerate()
        return SidecarBulkReadResult(records: [], diagnostics: SidecarBulkReadDiagnostics())
    }
}

@Suite("PR #148 Security-Scoped Search")
struct PR148SecurityScopedSearchTests {
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr148-scoped-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test("bulk sidecar reading occurs inside the scoped-access callback")
    func bulkReadOccursWithinScopedAccess() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeRoot = FakeRootAccess()
        var depthDuringRead: Int?
        let fakeReader = FakeSidecarBulkReader {
            depthDuringRead = fakeRoot.currentDepth
        }

        let settings = LibrarySettings(
            rootPath: tmp.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        _ = try useCase.execute(
            query: WorkflowSearchQuery(rawText: ""),
            settings: settings,
            libraryRootURL: tmp,
            sidecarBulkReader: fakeReader,
            rootAccess: fakeRoot
        )

        #expect(fakeRoot.withAccessCallCount == 1, "bulk read must happen inside exactly one withAccess scope")
        #expect(depthDuringRead == 1, "enumerateSidecars must run while security-scoped access is active")
    }

    @Test("missing bookmark still throws before any scoped access is attempted")
    func missingBookmarkStillThrows() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeRoot = FakeRootAccess()
        fakeRoot.stubbedStatus = .missingBookmark
        let fakeReader = FakeSidecarBulkReader {}

        let settings = LibrarySettings(
            rootPath: tmp.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        #expect(throws: AppError.self) {
            _ = try useCase.execute(
                query: WorkflowSearchQuery(rawText: ""),
                settings: settings,
                libraryRootURL: tmp,
                sidecarBulkReader: fakeReader,
                rootAccess: fakeRoot
            )
        }
        #expect(fakeRoot.withAccessCallCount == 0, "must not attempt scoped access when the bookmark is missing")
    }

    @Test("stale bookmark still throws before any scoped access is attempted")
    func staleBookmarkStillThrows() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeRoot = FakeRootAccess()
        fakeRoot.stubbedStatus = .staleBookmark(rootURL: tmp)
        let fakeReader = FakeSidecarBulkReader {}

        let settings = LibrarySettings(
            rootPath: tmp.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let useCase = SearchWorkflowMeasurementsUseCase()
        #expect(throws: AppError.self) {
            _ = try useCase.execute(
                query: WorkflowSearchQuery(rawText: ""),
                settings: settings,
                libraryRootURL: tmp,
                sidecarBulkReader: fakeReader,
                rootAccess: fakeRoot
            )
        }
        #expect(fakeRoot.withAccessCallCount == 0, "must not attempt scoped access when the bookmark is stale")
    }
}
