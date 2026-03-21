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
    static let shared = AppLogger()
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
}
