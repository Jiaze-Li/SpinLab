import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.4.2 Workbench Results Read Model")
struct V342WorkbenchResultsReadModelTests {

    // MARK: - Helpers

    private func makeFixture() throws -> (resolver: LibraryPathResolver, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v342-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryPathResolver(libraryRootURL: root), root)
    }

    private func cleanup(_ root: URL) { try? FileManager.default.removeItem(at: root) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private func writeIndex(
        _ index: WorkbenchResultsIndex,
        sampleKey: String,
        root: URL
    ) throws {
        let dir = root
            .appending(path: "samples/\(sampleKey)/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "results_index.json")
        try Self.encoder.encode(index).write(to: url)
    }

    private func makeRef(workflowID: String = "AHE") -> WorkbenchResultReference {
        WorkbenchResultReference(
            chartIdentityKey: UUID().uuidString,
            chartImagePath: "analysis/workflows/\(workflowID)/charts/chart.png",
            manifestPath: "analysis/workflows/\(workflowID)/manifests/manifest.json",
            workflowID: workflowID,
            generatedAt: Date(timeIntervalSince1970: 1_712_146_400)
        )
    }

    // MARK: - Missing file → nil

    @Test("use case returns nil when results_index.json is absent")
    func missingFileReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let result = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-MISSING")
        #expect(result == nil)
    }

    // MARK: - Valid index → all references present

    @Test("use case returns index with all references for a valid file")
    func validIndexReturnsBothReferences() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let ref1 = makeRef(workflowID: "AHE")
        let ref2 = makeRef(workflowID: "AHE-2")
        let index = WorkbenchResultsIndex(
            sampleKey: "SK-A",
            updatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            references: [ref1, ref2]
        )
        try writeIndex(index, sampleKey: "SK-A", root: root)

        let loaded = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-A")
        #expect(loaded != nil)
        #expect(loaded?.references.count == 2)
        #expect(loaded?.sampleKey == "SK-A")
    }

    // MARK: - Schema version mismatch → nil

    @Test("use case returns nil when schemaVersion is not 1")
    func schemaMismatchReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        // Build a valid index then manually patch schemaVersion to 99
        let index = WorkbenchResultsIndex(
            sampleKey: "SK-B",
            updatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            references: [makeRef()]
        )
        var encoded = try Self.encoder.encode(index)
        // Replace "schemaVersion" : 1 → 99 in the JSON bytes
        if var str = String(data: encoded, encoding: .utf8) {
            str = str.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
            encoded = str.data(using: .utf8)!
        }
        let dir = root.appending(path: "samples/SK-B/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoded.write(to: dir.appending(path: "results_index.json"))

        let result = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-B")
        #expect(result == nil)
    }

    // MARK: - Corrupt JSON → nil, no crash (Adj-10)

    @Test("use case returns nil for corrupt JSON without crashing")
    func corruptJSONReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let dir = root.appending(path: "samples/SK-C/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not valid json %%%".utf8).write(to: dir.appending(path: "results_index.json"))

        let result = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-C")
        #expect(result == nil)
    }

    // MARK: - Truncated file → nil, no crash (Adj-10)

    @Test("use case returns nil for truncated file without crashing")
    func truncatedFileReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let index = WorkbenchResultsIndex(
            sampleKey: "SK-D",
            updatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            references: [makeRef()]
        )
        let full = try Self.encoder.encode(index)
        let truncated = full.prefix(full.count / 2)

        let dir = root.appending(path: "samples/SK-D/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try truncated.write(to: dir.appending(path: "results_index.json"))

        let result = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-D")
        #expect(result == nil)
    }

    // MARK: - Round B: WorkbenchResultsSectionView data conditions

    @Test("projection with references satisfies reference-list rendering condition")
    func projectionWithReferencesIsNonEmpty() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let ref1 = makeRef(workflowID: "AHE")
        let ref2 = makeRef(workflowID: "AHE-2")
        let index = WorkbenchResultsIndex(
            sampleKey: "SK-E",
            updatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            references: [ref1, ref2]
        )
        try writeIndex(index, sampleKey: "SK-E", root: root)

        let loaded = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-E")
        // Section renders reference list when projection is non-nil and references non-empty
        #expect(loaded?.references.isEmpty == false)
        #expect(loaded?.references.count == 2)
    }

    @Test("nil projection satisfies empty-state rendering condition")
    func nilProjectionSatisfiesEmptyState() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        // No file written for SK-F → use case returns nil → section shows empty state
        let loaded = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: "SK-F")
        #expect(loaded == nil)
    }

    // MARK: - Store projection trigger timing (Fix-1 / Issue-2 coverage)

    @Test("loadWorkbenchResultsForCurrentSelection populates workbenchResults when sample and root are set")
    @MainActor
    func storeProjectionPopulatesWhenSelectionAndRootAreSet() throws {
        let (_, root) = try makeFixture()
        defer { cleanup(root) }

        // Write a valid index for the sample that will be "selected"
        let ref = makeRef(workflowID: "AHE")
        let index = WorkbenchResultsIndex(
            sampleKey: "SK-G",
            updatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            references: [ref]
        )
        try writeIndex(index, sampleKey: "SK-G", root: root)

        let store = LibraryFeatureStore()
        store.librarySelectedSampleId = "SK-G"
        store.librarySettings.rootPath = root.path

        store.loadWorkbenchResultsForCurrentSelection()

        #expect(store.workbenchResults != nil)
        #expect(store.workbenchResults?.sampleKey == "SK-G")
        #expect(store.workbenchResults?.references.count == 1)
    }

    @Test("loadWorkbenchResultsForCurrentSelection yields nil when no sample is selected")
    @MainActor
    func storeProjectionIsNilWhenNoSampleSelected() {
        let store = LibraryFeatureStore()
        store.librarySelectedSampleId = nil
        store.librarySettings.rootPath = "/some/path"

        store.loadWorkbenchResultsForCurrentSelection()

        #expect(store.workbenchResults == nil)
    }

    @Test("loadWorkbenchResultsForCurrentSelection yields nil when library root is not set")
    @MainActor
    func storeProjectionIsNilWhenRootNotSet() {
        let store = LibraryFeatureStore()
        store.librarySelectedSampleId = "SK-H"
        store.librarySettings.rootPath = nil

        store.loadWorkbenchResultsForCurrentSelection()

        #expect(store.workbenchResults == nil)
    }
}
