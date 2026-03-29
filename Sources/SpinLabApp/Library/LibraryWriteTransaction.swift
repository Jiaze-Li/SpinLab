import Foundation

struct LibraryWriteTransaction {
    private struct PreparedWrite {
        var temporaryURL: URL
        var destinationURL: URL
    }

    private let fileManager: FileManager = .default
    private let transactionRootURL: URL
    private var preparedWrites: [PreparedWrite] = []
    private var committedDestinations: [URL] = []

    init() {
        transactionRootURL = fileManager.temporaryDirectory
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

    mutating func commit() throws {
        do {
            for write in preparedWrites {
                let destinationParent = write.destinationURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
                try fileManager.moveItem(at: write.temporaryURL, to: write.destinationURL)
                committedDestinations.append(write.destinationURL)
            }
            try cleanup()
        } catch {
            try rollback()
            throw error
        }
    }

    mutating func rollback() throws {
        for destination in committedDestinations {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
        }
        for write in preparedWrites {
            if fileManager.fileExists(atPath: write.temporaryURL.path) {
                try? fileManager.removeItem(at: write.temporaryURL)
            }
        }
        try cleanup()
    }

    private mutating func cleanup() throws {
        if fileManager.fileExists(atPath: transactionRootURL.path) {
            try? fileManager.removeItem(at: transactionRootURL)
        }
        preparedWrites = []
        committedDestinations = []
    }
}
