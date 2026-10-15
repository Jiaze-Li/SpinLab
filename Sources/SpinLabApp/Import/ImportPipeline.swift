import Foundation

/// Generic import filtering + pending-import construction for one workflow.
///
/// Rule Book SSOT: `supportedFileExtensions`/`ignoredFileExtensions` are NOT captured once in
/// `init` — they are computed properties that re-read `ruleProvider.importRules()` on every
/// access. `SpinLabAppState` builds one pipeline instance per workflow and keeps it for the
/// app's lifetime; because extension filtering is read live, a Rules Book save (e.g. adding a
/// new supported extension) is visible on the very next import/scan through that same instance,
/// with no reconstruction and no format-specific special case required here.
struct SpinLabImportPipeline {
    let workflowExtension: WorkflowExtension
    let metadataExtension: MetadataExtension
    private let ruleProvider: any SpinLabRuleProviding

    /// Read live from the active Rule Book on every access — never snapshotted at init,
    /// so a Rules save is reflected on the very next call without reconstructing this pipeline.
    var supportedFileExtensions: Set<String> {
        Set(ruleProvider.importRules().supportedFileExtensions.map { $0.lowercased() })
    }

    var ignoredFileExtensions: Set<String> {
        Set(ruleProvider.importRules().ignoredFileExtensions.map { $0.lowercased() })
    }

    init(
        workflowExtension: WorkflowExtension,
        metadataExtension: MetadataExtension,
        ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared
    ) {
        self.workflowExtension = workflowExtension
        self.metadataExtension = metadataExtension
        self.ruleProvider = ruleProvider
    }

    func importFiles(_ files: [ImportedMeasurementFile]) -> [SpinLabDomain.PendingImport] {
        let supported = supportedFileExtensions
        let ignored = ignoredFileExtensions
        return files.compactMap { file in
            let ext = file.sourceFileURL.pathExtension.lowercased()
            guard !ext.isEmpty else {
                return nil
            }
            guard !ignored.contains(ext), supported.contains(ext) else {
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
