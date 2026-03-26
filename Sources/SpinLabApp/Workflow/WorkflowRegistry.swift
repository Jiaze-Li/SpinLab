import Foundation

struct WorkflowBundle {
    let workflowExtension: WorkflowExtension
    let metadataExtension: MetadataExtension
    let analysisModule: AnalysisModuleExtension
    let viewExtension: ViewExtension

    var importPipeline: SpinLabImportPipeline {
        SpinLabImportPipeline(
            workflowExtension: workflowExtension,
            metadataExtension: metadataExtension
        )
    }
}

final class WorkflowRegistry {
    static let shared = WorkflowRegistry()

    private var bundlesByKind: [SpinLabDomain.WorkflowKind: WorkflowBundle] = [:]
    private var fallbackKind: SpinLabDomain.WorkflowKind = .amrPhe

    private init() {
        registerBuiltins()
    }

    func register(_ bundle: WorkflowBundle) {
        bundlesByKind[bundle.workflowExtension.workflow] = bundle
    }

    func setDefaultWorkflow(_ workflow: SpinLabDomain.WorkflowKind) {
        fallbackKind = workflow
    }

    func bundle(for workflow: SpinLabDomain.WorkflowKind) -> WorkflowBundle? {
        bundlesByKind[workflow]
    }

    func defaultBundle() -> WorkflowBundle {
        if let configured = bundlesByKind[fallbackKind] {
            return configured
        }
        if let first = bundlesByKind.values.first {
            return first
        }

        // Emergency fallback: registry should always be bootstrapped with builtins.
        return WorkflowBundle(
            workflowExtension: AMRPHEWorkflowExtension(),
            metadataExtension: AMRPHEMetadataExtension(),
            analysisModule: AMRPHEAnalysisModuleExtension(),
            viewExtension: AMRPHEViewExtension()
        )
    }

    private func registerBuiltins() {
        register(
            WorkflowBundle(
                workflowExtension: AMRPHEWorkflowExtension(),
                metadataExtension: AMRPHEMetadataExtension(),
                analysisModule: AMRPHEAnalysisModuleExtension(),
                viewExtension: AMRPHEViewExtension()
            )
        )
        register(
            WorkflowBundle(
                workflowExtension: DummyWorkflowExtension(),
                metadataExtension: DummyMetadataExtension(),
                analysisModule: DummyAnalysisModuleExtension(),
                viewExtension: DummyViewExtension()
            )
        )
    }
}
