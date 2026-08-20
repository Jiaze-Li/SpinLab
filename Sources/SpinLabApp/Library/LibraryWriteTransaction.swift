import Foundation

/// Narrow filesystem seam so `LibraryWriteTransaction` can be exercised under
/// deterministic fault injection (e.g. "second move fails", "rollback delete
/// fails") without depending on real disk-failure conditions. `FileManager`
/// conforms directly for production use.
protocol LibraryWriteTransactionFileSystem {
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func removeItem(at url: URL) throws
}

extension FileManager: LibraryWriteTransactionFileSystem {
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
    }
}

struct LibraryWriteTransaction {
    /// Reports any artifact this transaction could not clean up during rollback.
    /// A non-nil failure means at least one destination (already moved into place)
    /// or staged temporary file survived the rollback attempt — callers must not
    /// treat that as a clean failure.
    struct RollbackFailure: Error, LocalizedError {
        var survivingDestinationURLs: [URL]
        var survivingTemporaryURLs: [URL]

        var errorDescription: String? {
            var parts: [String] = []
            if !survivingDestinationURLs.isEmpty {
                parts.append("surviving destinations: \(survivingDestinationURLs.map(\.path).joined(separator: ", "))")
            }
            if !survivingTemporaryURLs.isEmpty {
                parts.append("surviving temp files: \(survivingTemporaryURLs.map(\.path).joined(separator: ", "))")
            }
            return "Rollback incomplete (\(parts.joined(separator: "; ")))."
        }
    }

    /// Thrown by `commit()` when the write batch failed *and* rollback could not
    /// fully clean up what it had already committed. Wraps the original commit
    /// error so callers keep both pieces of context instead of one silently
    /// hiding the other.
    struct CommitFailure: Error, LocalizedError {
        var underlyingError: Error
        var rollbackFailure: RollbackFailure

        var errorDescription: String? {
            let underlyingMessage = (underlyingError as? LocalizedError)?.errorDescription
                ?? String(describing: underlyingError)
            let rollbackMessage = rollbackFailure.errorDescription ?? "rollback incomplete."
            return "\(underlyingMessage) — \(rollbackMessage)"
        }
    }

    private struct PreparedWrite {
        var temporaryURL: URL
        var destinationURL: URL
    }

    private let fileManager: LibraryWriteTransactionFileSystem
    private let transactionRootURL: URL
    private var preparedWrites: [PreparedWrite] = []
    private var committedDestinations: [URL] = []
    private static let sidecarEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(fileManager: LibraryWriteTransactionFileSystem = FileManager.default) {
        self.fileManager = fileManager
        transactionRootURL = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-apply-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    mutating func prepare(sourceURL: URL, destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.notFound("Source file not found: \(sourceURL.path)")
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw AppError.state("Destination already exists: \(destinationURL.path)")
        }

        try fileManager.createDirectory(at: transactionRootURL, withIntermediateDirectories: true)
        let tempURL = transactionRootURL.appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try fileManager.copyItem(at: sourceURL, to: tempURL)
        preparedWrites.append(PreparedWrite(temporaryURL: tempURL, destinationURL: destinationURL))
    }

    mutating func prepareSidecar(_ sidecar: SpinLabFileSidecar, destinationURL: URL) throws {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw AppError.state("Destination already exists: \(destinationURL.path)")
        }

        try fileManager.createDirectory(at: transactionRootURL, withIntermediateDirectories: true)
        let tempURL = transactionRootURL.appending(path: UUID().uuidString + ".json", directoryHint: .notDirectory)
        let data = try Self.sidecarEncoder.encode(sidecar)
        try data.write(to: tempURL)
        preparedWrites.append(PreparedWrite(temporaryURL: tempURL, destinationURL: destinationURL))
    }

    /// Moves every staged write into its real destination. If any move fails,
    /// already-committed destinations and remaining staged temp files are
    /// rolled back before rethrowing. If that rollback itself cannot fully
    /// clean up, throws `CommitFailure` wrapping both the original error and
    /// the rollback failure — otherwise rethrows the original error unchanged.
    mutating func commit() throws {
        do {
            for write in preparedWrites {
                let destinationParent = write.destinationURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
                try fileManager.moveItem(at: write.temporaryURL, to: write.destinationURL)
                committedDestinations.append(write.destinationURL)
            }
            cleanup()
        } catch {
            if let rollbackFailure = rollback() {
                throw CommitFailure(underlyingError: error, rollbackFailure: rollbackFailure)
            }
            throw error
        }
    }

    /// Deletes every artifact this transaction is responsible for
    /// (already-committed destinations, then remaining staged temp files),
    /// continuing past individual failures rather than stopping at the first
    /// one. Returns `nil` when everything was removed cleanly, otherwise a
    /// `RollbackFailure` naming what survived — callers must not treat that
    /// as a clean rollback.
    @discardableResult
    mutating func rollback() -> RollbackFailure? {
        var survivingDestinations: [URL] = []
        for destination in committedDestinations {
            if fileManager.fileExists(atPath: destination.path) {
                do {
                    try fileManager.removeItem(at: destination)
                } catch {
                    survivingDestinations.append(destination)
                }
            }
        }

        var survivingTemporaries: [URL] = []
        for write in preparedWrites {
            if fileManager.fileExists(atPath: write.temporaryURL.path) {
                do {
                    try fileManager.removeItem(at: write.temporaryURL)
                } catch {
                    survivingTemporaries.append(write.temporaryURL)
                }
            }
        }

        cleanup()

        guard !survivingDestinations.isEmpty || !survivingTemporaries.isEmpty else {
            return nil
        }
        return RollbackFailure(
            survivingDestinationURLs: survivingDestinations,
            survivingTemporaryURLs: survivingTemporaries
        )
    }

    private mutating func cleanup() {
        if fileManager.fileExists(atPath: transactionRootURL.path) {
            try? fileManager.removeItem(at: transactionRootURL)
        }
        preparedWrites = []
        committedDestinations = []
    }
}
