import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.12 InboxArchiveApplyService Rollback FailSoft", .serialized)
struct V5112InboxArchiveRollbackFailSoftTests {

    private func makeTmpDir(_ tag: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v5112-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func emptyIndex() -> LibraryIndex {
        LibraryIndex(
            createdAt: .now,
            updatedAt: .now,
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [],
            samples: []
        )
    }

    private func makePending(fileName: String, sourceDir: URL) throws -> SpinLabDomain.PendingImport {
        let sourceURL = sourceDir.appendingPathComponent(fileName)
        try Data("test-content".utf8).write(to: sourceURL)
        return SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: sourceURL.path,
            originalFilePath: sourceURL.path,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
    }

    // MARK: - Tests

    @Test("drawerNotFound error propagates after rollback attempt")
    func drawerNotFoundPropagates() throws {
        let root = try makeTmpDir("drawer-missing")
        defer { try? FileManager.default.removeItem(at: root) }

        let pending = try makePending(fileName: "unknown_sample.dat", sourceDir: root)
        let target = SpinLabDomain.RouteTarget(sampleId: "NO_SUCH_SAMPLE", channels: ["file"])
        let service = InboxArchiveApplyService()

        var caughtError: (any Error)? = nil
        do {
            _ = try service.apply(
                pending: pending,
                targets: [target],
                libraryIndex: emptyIndex(),
                libraryStore: LibraryStore(),
                libraryRootURL: root
            )
        } catch {
            caughtError = error
        }

        guard let applyError = caughtError as? InboxArchiveApplyService.InboxArchiveApplyError else {
            Issue.record("Expected InboxArchiveApplyError, got: \(String(describing: caughtError))")
            return
        }
        if case .drawerNotFound = applyError { } else {
            Issue.record("Expected drawerNotFound, got: \(applyError)")
        }
    }

    @Test("sourceFileNotFound error propagates after rollback attempt")
    func sourceFileNotFoundPropagates() throws {
        let root = try makeTmpDir("src-missing")
        defer { try? FileManager.default.removeItem(at: root) }

        let pending = SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: "nonexistent.dat",
            sourceFilePath: root.appendingPathComponent("nonexistent.dat").path,
            originalFilePath: root.appendingPathComponent("nonexistent.dat").path,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
        let target = SpinLabDomain.RouteTarget(sampleId: "PN99", channels: ["file"])
        let service = InboxArchiveApplyService()

        var caughtError: (any Error)? = nil
        do {
            _ = try service.apply(
                pending: pending,
                targets: [target],
                libraryIndex: emptyIndex(),
                libraryStore: LibraryStore(),
                libraryRootURL: root
            )
        } catch {
            caughtError = error
        }

        guard let applyError = caughtError as? InboxArchiveApplyService.InboxArchiveApplyError else {
            Issue.record("Expected InboxArchiveApplyError, got: \(String(describing: caughtError))")
            return
        }
        if case .sourceFileNotFound = applyError { } else {
            Issue.record("Expected sourceFileNotFound, got: \(applyError)")
        }
    }
}
