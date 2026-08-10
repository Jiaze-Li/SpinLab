import Foundation

struct SidecarRecord: Sendable {
    let sidecar: SpinLabFileSidecar
    let sidecarURL: URL
}

struct SidecarBulkReadDiagnostics: Sendable, Equatable {
    var skippedCount: Int = 0
    var skippedPaths: [String] = []
}

struct SidecarBulkReadResult: Sendable {
    let records: [SidecarRecord]
    let diagnostics: SidecarBulkReadDiagnostics
}

protocol LibrarySidecarBulkReaderCapability {
    func enumerateSidecars(rootURL: URL, fileManager: FileManager) -> SidecarBulkReadResult
}

/// Canonical bulk sidecar reader. Any code that needs to read every sidecar
/// under a Library root (or a subtree of one) must go through this rather
/// than walking the filesystem and decoding `*.spinlab.json` files itself.
///
/// Decoding always goes through `LibrarySidecarReader` (Skip + Warning):
/// a corrupt or unreadable sidecar is skipped and logged, never thrown and
/// never silently dropped, so one bad file never blocks access to the rest
/// of the Library.
struct LibrarySidecarBulkReader: LibrarySidecarBulkReaderCapability {
    private let reader: any LibrarySidecarReaderCapability
    private let logger: any AppLogging

    init(
        reader: any LibrarySidecarReaderCapability = LibrarySidecarReader(),
        logger: any AppLogging = AppLogger.shared
    ) {
        self.reader = reader
        self.logger = logger
    }

    func enumerateSidecars(rootURL: URL, fileManager: FileManager = .default) -> SidecarBulkReadResult {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SidecarBulkReadResult(records: [], diagnostics: SidecarBulkReadDiagnostics())
        }

        var records: [SidecarRecord] = []
        var diagnostics = SidecarBulkReadDiagnostics()

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }

            switch reader.loadSidecar(at: url) {
            case .success(let sidecar):
                records.append(SidecarRecord(sidecar: sidecar, sidecarURL: url))
            case .failure(let error):
                diagnostics.skippedCount += 1
                diagnostics.skippedPaths.append(url.path)
                logger.warning(.library, "Skipping unreadable or corrupt sidecar",
                                metadata: ["path": url.path, "reason": String(describing: error)])
            }
        }

        return SidecarBulkReadResult(records: records, diagnostics: diagnostics)
    }
}
