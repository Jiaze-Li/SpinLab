import Foundation
import Testing
@testable import SpinLabApp

/// Deterministic fault injection for `LibraryWriteTransaction.commit()`/`rollback()`.
/// Wraps the real `FileManager` for every operation except `moveItem`/`removeItem`
/// calls whose destination path is explicitly configured to fail, so tests can force
/// "first move succeeds, second move fails" and "rollback delete itself fails"
/// without relying on real disk-failure conditions.
private final class FaultInjectingFileSystem: LibraryWriteTransactionFileSystem {
    private let real = FileManager.default
    var moveItemFailurePaths: Set<String> = []
    var removeItemFailurePaths: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        real.fileExists(atPath: path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try real.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try real.copyItem(at: srcURL, to: dstURL)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if moveItemFailurePaths.contains(dstURL.path) {
            throw AppError.io("injected move failure: \(dstURL.path)")
        }
        try real.moveItem(at: srcURL, to: dstURL)
    }

    func removeItem(at url: URL) throws {
        if removeItemFailurePaths.contains(url.path) {
            throw AppError.io("injected remove failure: \(url.path)")
        }
        try real.removeItem(at: url)
    }
}

@Suite("LibraryWriteTransaction rollback")
struct LibraryWriteTransactionRollbackTests {
    private func makeSources(in rootURL: URL) throws -> (first: URL, second: URL) {
        let first = rootURL.appending(path: "first.dat", directoryHint: .notDirectory)
        let second = rootURL.appending(path: "second.dat", directoryHint: .notDirectory)
        try Data("first-artifact".utf8).write(to: first)
        try Data("second-artifact".utf8).write(to: second)
        return (first, second)
    }

    @Test("second move failing after first succeeds rolls back the already-committed first destination")
    func secondMoveFailureRollsBackFirstDestination() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-lwt-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let (firstSource, secondSource) = try makeSources(in: rootURL)
        let firstDestination = rootURL.appending(path: "dest/first.dat", directoryHint: .notDirectory)
        let secondDestination = rootURL.appending(path: "dest/second.dat", directoryHint: .notDirectory)

        let faultySystem = FaultInjectingFileSystem()
        faultySystem.moveItemFailurePaths = [secondDestination.path]

        var transaction = LibraryWriteTransaction(fileManager: faultySystem)
        try transaction.prepare(sourceURL: firstSource, destinationURL: firstDestination)
        try transaction.prepare(sourceURL: secondSource, destinationURL: secondDestination)

        #expect(throws: (any Error).self) {
            try transaction.commit()
        }

        #expect(!FileManager.default.fileExists(atPath: firstDestination.path))
        #expect(!FileManager.default.fileExists(atPath: secondDestination.path))
    }

    @Test("second move failing plus rollback delete failing surfaces an incomplete rollback with the surviving artifact intact")
    func rollbackDeleteFailureSurfacesIncompleteRollback() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-lwt-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let (firstSource, secondSource) = try makeSources(in: rootURL)
        let firstDestination = rootURL.appending(path: "dest/first.dat", directoryHint: .notDirectory)
        let secondDestination = rootURL.appending(path: "dest/second.dat", directoryHint: .notDirectory)

        let faultySystem = FaultInjectingFileSystem()
        faultySystem.moveItemFailurePaths = [secondDestination.path]
        faultySystem.removeItemFailurePaths = [firstDestination.path]

        var transaction = LibraryWriteTransaction(fileManager: faultySystem)
        try transaction.prepare(sourceURL: firstSource, destinationURL: firstDestination)
        try transaction.prepare(sourceURL: secondSource, destinationURL: secondDestination)

        var caughtError: Error?
        do {
            try transaction.commit()
            Issue.record("Expected commit to throw when a downstream move fails.")
        } catch {
            caughtError = error
        }

        guard let commitFailure = caughtError as? LibraryWriteTransaction.CommitFailure else {
            Issue.record("Expected LibraryWriteTransaction.CommitFailure when rollback cannot fully clean up, got \(String(describing: caughtError)).")
            return
        }

        // Rollback is surfaced as incomplete rather than the caller silently
        // seeing a clean failure.
        #expect(commitFailure.rollbackFailure.survivingDestinationURLs.map(\.path) == [firstDestination.path])
        #expect(commitFailure.rollbackFailure.errorDescription?.isEmpty == false)

        // The artifact rollback could not remove is genuinely still on disk —
        // this is exactly the orphan a caller must not mistake for a clean failure.
        #expect(FileManager.default.fileExists(atPath: firstDestination.path))
        #expect(!FileManager.default.fileExists(atPath: secondDestination.path))
    }

    @Test("rollback continues cleaning up remaining artifacts after one delete failure")
    func rollbackContinuesAfterOneDeleteFailure() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-lwt-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let (firstSource, secondSource) = try makeSources(in: rootURL)
        let firstDestination = rootURL.appending(path: "dest/first.dat", directoryHint: .notDirectory)
        let secondDestination = rootURL.appending(path: "dest/second.dat", directoryHint: .notDirectory)
        let thirdSource = rootURL.appending(path: "third.dat", directoryHint: .notDirectory)
        try Data("third-artifact".utf8).write(to: thirdSource)
        let thirdDestination = rootURL.appending(path: "dest/third.dat", directoryHint: .notDirectory)

        let faultySystem = FaultInjectingFileSystem()
        // First two moves succeed and commit; the third move fails, triggering
        // rollback of both committed destinations. Only the first delete is
        // injected to fail — the second must still be cleaned up.
        faultySystem.moveItemFailurePaths = [thirdDestination.path]
        faultySystem.removeItemFailurePaths = [firstDestination.path]

        var transaction = LibraryWriteTransaction(fileManager: faultySystem)
        try transaction.prepare(sourceURL: firstSource, destinationURL: firstDestination)
        try transaction.prepare(sourceURL: secondSource, destinationURL: secondDestination)
        try transaction.prepare(sourceURL: thirdSource, destinationURL: thirdDestination)

        #expect(throws: (any Error).self) {
            try transaction.commit()
        }

        // The one delete injected to fail leaves its artifact behind...
        #expect(FileManager.default.fileExists(atPath: firstDestination.path))
        // ...but rollback did not stop there — the second commit destination
        // (no injected failure) was still cleaned up.
        #expect(!FileManager.default.fileExists(atPath: secondDestination.path))
        #expect(!FileManager.default.fileExists(atPath: thirdDestination.path))
    }
}
