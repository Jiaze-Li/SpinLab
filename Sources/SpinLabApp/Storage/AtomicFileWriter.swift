import Darwin
import Foundation

struct AtomicWriteEntry: Sendable {
    var destinationURL: URL
    var data: Data
}

protocol AtomicFileWritingCapability {
    func commit(_ entries: [AtomicWriteEntry]) throws
    func write(_ data: Data, to destinationURL: URL) throws
}

struct AtomicFileWriter: AtomicFileWritingCapability {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func write(_ data: Data, to destinationURL: URL) throws {
        try commit([AtomicWriteEntry(destinationURL: destinationURL, data: data)])
    }

    func commit(_ entries: [AtomicWriteEntry]) throws {
        if entries.isEmpty {
            return
        }

        struct PreparedEntry {
            var temporaryURL: URL
            var destinationURL: URL
            var parentURL: URL
        }

        var prepared: [PreparedEntry] = []
        do {
            for entry in entries {
                let parentURL = entry.destinationURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

                let temporaryURL = parentURL.appending(path: ".spinlab-tmp-\(UUID().uuidString)", directoryHint: .notDirectory)
                try entry.data.write(to: temporaryURL)
                try syncFile(at: temporaryURL)
                prepared.append(PreparedEntry(temporaryURL: temporaryURL, destinationURL: entry.destinationURL, parentURL: parentURL))
            }

            for item in prepared {
                if fileManager.fileExists(atPath: item.destinationURL.path) {
                    _ = try fileManager.replaceItemAt(item.destinationURL, withItemAt: item.temporaryURL)
                } else {
                    try fileManager.moveItem(at: item.temporaryURL, to: item.destinationURL)
                }
                try syncDirectory(at: item.parentURL)
            }
        } catch {
            for item in prepared where fileManager.fileExists(atPath: item.temporaryURL.path) {
                try? fileManager.removeItem(at: item.temporaryURL)
            }
            throw AppError.io("Atomic write failed: \(error.localizedDescription)")
        }
    }

    private func syncFile(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw AppError.io("open() failed for file: \(url.path)")
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw AppError.io("fsync() failed for file: \(url.path)")
        }
    }

    private func syncDirectory(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw AppError.io("open() failed for directory: \(url.path)")
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw AppError.io("fsync() failed for directory: \(url.path)")
        }
    }
}
