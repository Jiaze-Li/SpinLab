import Foundation

struct LibraryPreviewParseSnapshot: Sendable {
    let index: LibraryIndex
    let warnings: [LibraryWarning]
}

protocol SpinLabDataActing: Sendable {
    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot
    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot
    func searchWorkflowMeasurements(libraryRootPath: String, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) async throws -> [WorkflowMeasurementSearchHit]
}

actor SpinLabDataActor: SpinLabDataActing {
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
        let result = try parser.parse(xlsxURL: URL(fileURLWithPath: registryPath), settings: settings)
        if result.warnings.contains(where: { $0.severity == .error }) {
            let message = result.warnings
                .first(where: { $0.severity == .error })?
                .message ?? "Failed to parse library preview from registry."
            throw AppError.io(message)
        }
        return LibraryPreviewParseSnapshot(index: result.index, warnings: result.warnings)
    }

    func searchWorkflowMeasurements(libraryRootPath: String, query: WorkflowSearchQuery, workflowDefinitions: [WorkflowDefinition]) throws -> [WorkflowMeasurementSearchHit] {
        let normalizedPath = libraryRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw AppError.validation("Library root path is required for workflow search.")
        }
        let rootURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
        let useCase = SearchWorkflowMeasurementsUseCase()
        do {
            return try useCase.execute(query: query, libraryRootURL: rootURL, workflowDefinitions: workflowDefinitions)
        } catch {
            throw AppError.from(error, fallback: "Workflow search failed.")
        }
    }
}
