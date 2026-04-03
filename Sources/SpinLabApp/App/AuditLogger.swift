import Foundation

final class AuditLogger {
    nonisolated(unsafe) static let shared = AuditLogger()

    private let fileManager: FileManager
    private let appSupportLogURL: URL
    private let maxLogFileBytes: Int
    private let lock = NSLock()
    private let encoder = JSONEncoder()

    init(
        fileManager: FileManager = .default,
        appSupportBaseURL: URL? = nil,
        maxLogFileBytes: Int = 1_048_576
    ) {
        self.fileManager = fileManager
        self.maxLogFileBytes = maxLogFileBytes
        encoder.outputFormatting = [.sortedKeys]

        let appSupportURL = appSupportBaseURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let logDirectory = appSupportURL
            .appending(path: "SpinLab", directoryHint: .isDirectory)
            .appending(path: "logs", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        appSupportLogURL = logDirectory.appending(path: "import_audit.log", directoryHint: .notDirectory)
    }

    func logImportEvent(_ event: AuditEvent, libraryRootURL: URL) {
        let libraryLogURL = libraryRootURL
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: "import_audit.log", directoryHint: .notDirectory)
        write(event: event, to: [appSupportLogURL, libraryLogURL])
    }

    func readLines(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func write(event: AuditEvent, to urls: [URL]) {
        guard let data = try? encoder.encode(event),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        for url in urls {
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try rotateIfNeeded(logURL: url)
                if fileManager.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    _ = try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                    try handle.close()
                } else {
                    try line.write(to: url, options: .atomic)
                }
            } catch {
                AppLogger.shared.warning(
                    .import,
                    "Import audit log write failed",
                    metadata: [
                        "logPath": url.path,
                        "reason": error.localizedDescription
                    ]
                )
            }
        }
    }

    private func rotateIfNeeded(logURL: URL) throws {
        guard fileManager.fileExists(atPath: logURL.path) else {
            return
        }
        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue >= maxLogFileBytes else {
            return
        }

        let archivedURL = logURL.deletingPathExtension()
            .appendingPathExtension(logURL.pathExtension + ".1")
        if fileManager.fileExists(atPath: archivedURL.path) {
            try fileManager.removeItem(at: archivedURL)
        }
        try fileManager.moveItem(at: logURL, to: archivedURL)
    }
}
