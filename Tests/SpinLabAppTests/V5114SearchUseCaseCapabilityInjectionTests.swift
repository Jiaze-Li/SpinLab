import Testing
import Foundation
@testable import SpinLabApp

// INV-7: SearchWorkflowMeasurementsUseCase accepts a LibraryAccessCapability
// and works without ever constructing LibraryStore() internally.

private final class FakeLibraryAccess: LibraryAccessCapability {
    private(set) var loadIndexCallCount = 0
    var stubbedIndex: LibraryIndex? = nil

    func loadIndex(from rootURL: URL) -> LibraryIndex? {
        loadIndexCallCount += 1
        return stubbedIndex
    }
}

@Suite("V5.1.14 Search UseCase Capability Injection")
struct V5114SearchUseCaseCapabilityInjectionTests {

    @Test("INV-7: execute with fake capability calls loadIndex on the fake, not LibraryStore")
    func useCaseCallsFakeLibraryAccess() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fake = FakeLibraryAccess()
        let useCase = SearchWorkflowMeasurementsUseCase()
        let query = WorkflowSearchQuery(rawText: "")
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

        let hits = try useCase.execute(
            query: query,
            settings: settings,
            libraryRootURL: tmp,
            workflowDefinitions: [],
            libraryAccess: fake
        )

        #expect(fake.loadIndexCallCount == 1, "fake loadIndex must be called once per execute")
        #expect(hits.isEmpty, "empty directory produces no hits")
    }

    @Test("INV-7b: fake capability returning nil index still produces empty hits (graceful)")
    func nilIndexGraceful() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv7b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fake = FakeLibraryAccess()
        fake.stubbedIndex = nil
        let useCase = SearchWorkflowMeasurementsUseCase()
        let query = WorkflowSearchQuery(rawText: "")
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

        let hits = try useCase.execute(
            query: query,
            settings: settings,
            libraryRootURL: tmp,
            workflowDefinitions: [],
            libraryAccess: fake
        )

        #expect(hits.isEmpty)
    }
}
