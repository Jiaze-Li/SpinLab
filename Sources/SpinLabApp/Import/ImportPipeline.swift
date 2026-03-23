import Foundation

struct SpinLabImportPipeline {
    let workflowExtension: WorkflowExtension
    let metadataExtension: MetadataExtension
    let supportedFileExtensions: Set<String> = ["csv", "txt", "dat", "lvm"]
    let ignoredFileExtensions: Set<String> = ["gph"]

    func importFiles(_ files: [ImportedMeasurementFile]) -> [SpinLabDomain.PendingImport] {
        files.compactMap { file in
            let ext = file.managedFileURL.pathExtension.lowercased()
            guard !ext.isEmpty else {
                return nil
            }
            guard !ignoredFileExtensions.contains(ext), supportedFileExtensions.contains(ext) else {
                return nil
            }

            let hints = metadataExtension.parseFilename(from: file.originalFileURL)
            return SpinLabDomain.PendingImport(
                workflow: workflowExtension.workflow,
                fileName: file.fileName,
                sourceFilePath: file.managedFileURL.path,
                originalFilePath: file.originalFileURL.path,
                status: .needsConfirmation,
                parsedHints: hints
            )
        }
    }

    static let amrPhe = SpinLabImportPipeline(
        workflowExtension: AMRPHEWorkflowExtension(),
        metadataExtension: AMRPHEMetadataExtension()
    )
}
