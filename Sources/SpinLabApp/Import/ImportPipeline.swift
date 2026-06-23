import Foundation

struct SpinLabImportPipeline {
    let workflowExtension: WorkflowExtension
    let metadataExtension: MetadataExtension
    let supportedFileExtensions: Set<String>
    let ignoredFileExtensions: Set<String>

    init(
        workflowExtension: WorkflowExtension,
        metadataExtension: MetadataExtension,
        ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared
    ) {
        self.workflowExtension = workflowExtension
        self.metadataExtension = metadataExtension

        let importRules = ruleProvider.importRules()
        supportedFileExtensions = Set(importRules.supportedFileExtensions.map { $0.lowercased() })
        ignoredFileExtensions = Set(importRules.ignoredFileExtensions.map { $0.lowercased() })
    }

    func importFiles(_ files: [ImportedMeasurementFile]) -> [SpinLabDomain.PendingImport] {
        files.compactMap { file in
            let ext = file.sourceFileURL.pathExtension.lowercased()
            guard !ext.isEmpty else {
                return nil
            }
            guard !ignoredFileExtensions.contains(ext), supportedFileExtensions.contains(ext) else {
                return nil
            }

            let hints = metadataExtension.parseFilename(from: file.originalFileURL)
            return SpinLabDomain.PendingImport(
                workflow: workflowExtension.workflow.legacyKind,
                fileName: file.fileName,
                sourceFilePath: file.sourceFileURL.path,
                originalFilePath: file.originalFileURL.path,
                status: .needsConfirmation,
                parsedHints: hints
            )
        }
    }

    static func fromBundle(_ bundle: WorkflowBundle) -> SpinLabImportPipeline {
        SpinLabImportPipeline(workflowExtension: bundle.workflowExtension, metadataExtension: bundle.metadataExtension)
    }
}
