import Foundation

enum AppLogLevel: String {
    case info
    case warning
    case error
}

enum AppLogCategory: String {
    case ui
    case usage
    case function
    case library
    case `import`
    case system
}

final class AppLogger {
    nonisolated(unsafe) static let shared = AppLogger()
    private static let maxLogFileBytes = 1_048_576
    private static let archivedLogFileName = "app_events.log.1"
    private static let redactedKeys: Set<String> = Set([
        "path",
        "sourcePath",
        "originalFilePath",
        "registryPath",
        "token",
        "key",
        "secret",
        "password",
        "apikey"
    ].map { $0.lowercased() })

    private struct LogEntry: Encodable {
        var timestamp: String
        var level: String
        var category: String
        var message: String
        var metadata: [String: String]
    }

    struct AuditTrailExport: Encodable {
        var exportedAt: String
        var context: [String: String]
        var entries: [String]
    }

    struct AuditTrailExportSummary {
        var entryCount: Int
    }

    private let fileManager = FileManager.default
    private let logURL: URL
    private let lock = NSLock()
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        let logsURL = spinLabURL.appending(path: "logs", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: logsURL, withIntermediateDirectories: true)
        logURL = logsURL.appending(path: "app_events.log")
    }

    func info(_ category: AppLogCategory, _ message: String, metadata: [String: String] = [:]) {
        write(level: .info, category: category, message: message, metadata: metadata)
    }

    func warning(_ category: AppLogCategory, _ message: String, metadata: [String: String] = [:]) {
        write(level: .warning, category: category, message: message, metadata: metadata)
    }

    func error(_ category: AppLogCategory, _ message: String, metadata: [String: String] = [:]) {
        write(level: .error, category: category, message: message, metadata: metadata)
    }

    private func write(level: AppLogLevel, category: AppLogCategory, message: String, metadata: [String: String]) {
        rotateIfNeeded()
        let entry = LogEntry(
            timestamp: timestampFormatter.string(from: Date()),
            level: level.rawValue,
            category: category.rawValue,
            message: message,
            metadata: sanitizedMetadata(metadata)
        )

        guard let data = try? JSONEncoder().encode(entry),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        if fileManager.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
                try? handle.close()
            }
        } else {
            try? line.write(to: logURL, options: .atomic)
        }
    }

    private func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(metadata.count)
        for (key, value) in metadata {
            let lowercased = key.lowercased()
            if Self.redactedKeys.contains(lowercased) || lowercased.hasSuffix("path") {
                sanitized[key] = "<redacted>"
            } else {
                sanitized[key] = value
            }
        }
        return sanitized
    }

    private func rotateIfNeeded() {
        guard fileManager.fileExists(atPath: logURL.path) else {
            return
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue >= Self.maxLogFileBytes else {
            return
        }

        let archivedURL = logURL.deletingLastPathComponent().appending(path: Self.archivedLogFileName)
        if fileManager.fileExists(atPath: archivedURL.path) {
            try? fileManager.removeItem(at: archivedURL)
        }
        try? fileManager.moveItem(at: logURL, to: archivedURL)
    }

    func exportAuditTrail(to destinationURL: URL, context: [String: String]) throws -> AuditTrailExportSummary {
        let exportedAt = timestampFormatter.string(from: Date())
        let lines = readLogLines()
        let payload = AuditTrailExport(
            exportedAt: exportedAt,
            context: sanitizedMetadata(context),
            entries: lines
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: destinationURL, options: .atomic)
        return AuditTrailExportSummary(entryCount: lines.count)
    }

    private func readLogLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let archivedURL = logURL.deletingLastPathComponent().appending(path: Self.archivedLogFileName)
        var urls: [URL] = []
        if fileManager.fileExists(atPath: archivedURL.path) {
            urls.append(archivedURL)
        }
        if fileManager.fileExists(atPath: logURL.path) {
            urls.append(logURL)
        }

        var lines: [String] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            lines.append(contentsOf: text.split(whereSeparator: \.isNewline).map(String.init))
        }
        return lines
    }
}
