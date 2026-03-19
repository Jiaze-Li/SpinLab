import Foundation

final class LibraryLogger {
    private let fileManager = FileManager.default
    private let logURL: URL

    init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        logURL = spinLabURL.appending(path: "library_warnings.log")
        try? fileManager.createDirectory(at: spinLabURL, withIntermediateDirectories: true)
    }

    func write(_ warnings: [LibraryWarning]) {
        guard !warnings.isEmpty else {
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entries = warnings.map { warning in
            let sample = warning.affectedSampleKey ?? "-"
            return "[\(timestamp)] [\(warning.severity.rawValue.uppercased())] \(sample) \(warning.message)"
        }
        let payload = entries.joined(separator: "\n") + "\n"
        if let data = payload.data(using: .utf8) {
            if fileManager.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
