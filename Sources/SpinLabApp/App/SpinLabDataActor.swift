import Foundation

struct LibraryPreviewParseSnapshot: Sendable {
    let index: LibraryIndex
    let warnings: [LibraryWarning]
}

actor SpinLabDataActor {
    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int = 10) throws -> SampleRegistrySnapshot {
        let index: XLSXPrefixSampleRegistryIndex
        do {
            index = try XLSXPrefixSampleRegistryIndex(xlsxURL: xlsxURL, previewRowCount: previewRowCount)
        } catch {
            throw AppError.from(error, fallback: "Failed to parse sample registry.")
        }
        return index.snapshot
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) throws -> LibraryPreviewParseSnapshot {
        guard FileManager.default.fileExists(atPath: registryPath) else {
            throw AppError.notFound("Registry file not found at \(registryPath).")
        }
        let parser = LibraryRegistryParser()
        let result = parser.parse(xlsxURL: URL(fileURLWithPath: registryPath), settings: settings)
        if result.warnings.contains(where: { $0.severity == .error }) {
            let message = result.warnings
                .first(where: { $0.severity == .error })?
                .message ?? "Failed to parse library preview from registry."
            throw AppError.io(message)
        }
        return LibraryPreviewParseSnapshot(index: result.index, warnings: result.warnings)
    }
}
