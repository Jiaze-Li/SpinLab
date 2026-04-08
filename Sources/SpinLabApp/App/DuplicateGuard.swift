import Foundation

struct DuplicateGuard {
    private let excludedOriginalPaths: Set<String>
    private let excludedContentFingerprints: Set<String>
    private let excludedFileNames: Set<String>
    private var seenOriginalPaths: Set<String> = []
    private var seenContentFingerprints: Set<String> = []
    private var seenFileNames: Set<String> = []

    init(
        excludedOriginalPaths: Set<String> = [],
        excludedContentFingerprints: Set<String> = [],
        excludedFileNames: Set<String> = []
    ) {
        self.excludedOriginalPaths = Set(excludedOriginalPaths.map(Self.normalizedPath))
        self.excludedContentFingerprints = Set(excludedContentFingerprints.map { $0.lowercased() })
        self.excludedFileNames = Set(excludedFileNames.map { $0.lowercased() })
    }

    mutating func accepts(
        originalPath: String,
        contentFingerprint: String?
    ) -> Bool {
        let normalizedPath = Self.normalizedPath(originalPath)
        guard !excludedOriginalPaths.contains(normalizedPath) else {
            return false
        }
        guard seenOriginalPaths.insert(normalizedPath).inserted else {
            return false
        }

        let fileName = URL(fileURLWithPath: originalPath).lastPathComponent.lowercased()
        guard !excludedFileNames.contains(fileName) else {
            return false
        }
        guard seenFileNames.insert(fileName).inserted else {
            return false
        }

        guard let contentFingerprint else {
            return true
        }

        let normalizedFingerprint = contentFingerprint.lowercased()
        guard !excludedContentFingerprints.contains(normalizedFingerprint) else {
            return false
        }
        guard seenContentFingerprints.insert(normalizedFingerprint).inserted else {
            return false
        }
        return true
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
