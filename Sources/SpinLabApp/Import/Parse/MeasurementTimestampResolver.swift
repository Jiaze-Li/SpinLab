import Foundation

/// Single shared entry point for turning a source measurement file into a
/// `SidecarMeasurementTimestamp`. This is the only place in the codebase that
/// parses PPMS FILEOPENTIME or an LVM filename timestamp prefix — no workflow
/// or parser should duplicate this logic.
struct MeasurementTimestampResolver {

    /// `fileURL` must point at the actual measurement file content to read
    /// (for .dat/.lvm parsing) and, for the .lvm fallback, is also the file whose
    /// `contentModificationDate` is captured. Callers on the Inbox write path must
    /// pass the *original* Inbox source file (before it is copied/moved), so the
    /// fallback reflects when the file was produced, not sidecar/import bookkeeping time.
    func resolve(fileURL: URL) -> SidecarMeasurementTimestamp {
        switch fileURL.pathExtension.lowercased() {
        case "dat":
            return resolveDAT(fileURL: fileURL)
        case "lvm":
            return resolveLVM(fileURL: fileURL)
        default:
            return .unknown
        }
    }

    // MARK: - PPMS .dat (FILEOPENTIME)

    private func resolveDAT(fileURL: URL) -> SidecarMeasurementTimestamp {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .unknown
        }
        return Self.parsePPMSFileOpenTime(from: content) ?? .unknown
    }

    private static let ppmsFileOpenTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // PPMS supplies no UTC offset — see SidecarMeasurementTimestamp doc comment.
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "M/d/yyyy,h:mm a"
        return formatter
    }()

    /// Shared PPMS FILEOPENTIME extraction path. Example header line:
    ///   `FILEOPENTIME,38091212.03,3/18/2026,1:24 PM`
    /// Column 0 is the marker, column 1 an instrument serial timestamp (ignored),
    /// column 2 the human-readable date, column 3 the human-readable time.
    static func parsePPMSFileOpenTime(from headerContent: String) -> SidecarMeasurementTimestamp? {
        for line in headerContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("FILEOPENTIME") else { continue }

            let parts = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4 else { return nil }

            let dateText = parts[2]
            let timeText = parts[3]
            let rawText = "\(dateText),\(timeText)"

            guard let date = ppmsFileOpenTimeFormatter.date(from: rawText) else {
                return SidecarMeasurementTimestamp(value: nil, provenance: .unknown, rawText: rawText)
            }
            return SidecarMeasurementTimestamp(value: date, provenance: .instrumentHeader, rawText: rawText)
        }
        return nil
    }

    // MARK: - .lvm (filename prefix, else filesystem fallback)

    private func resolveLVM(fileURL: URL) -> SidecarMeasurementTimestamp {
        if let parsed = Self.parseLVMFilenameTimestamp(from: fileURL.lastPathComponent) {
            return parsed
        }
        if let mtime = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return SidecarMeasurementTimestamp(value: mtime, provenance: .filesystemFallback, rawText: nil)
        }
        return .unknown
    }

    private static let lvmFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    private static let lvmFilenamePrefixPattern = #"^(\d{14})"#

    /// Production LVM filenames are prefixed with a `YYYYMMDDHHMMSS` timestamp,
    /// e.g. `20260430211659_...lvm` → 2026-04-30 21:16:59.
    static func parseLVMFilenameTimestamp(from filename: String) -> SidecarMeasurementTimestamp? {
        guard let regex = try? NSRegularExpression(pattern: lvmFilenamePrefixPattern) else { return nil }
        let range = NSRange(filename.startIndex..., in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              let prefixRange = Range(match.range(at: 1), in: filename) else {
            return nil
        }
        let rawText = String(filename[prefixRange])
        guard let date = lvmFilenameFormatter.date(from: rawText) else {
            return nil
        }
        return SidecarMeasurementTimestamp(value: date, provenance: .filename, rawText: rawText)
    }
}
