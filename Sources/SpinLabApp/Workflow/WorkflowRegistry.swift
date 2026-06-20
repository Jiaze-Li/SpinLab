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
    private let lock = NSLock()

    private init() {
        registerBuiltins()
    }

    func register(_ bundle: WorkflowBundle) {
        withLock {
            bundlesByKind[bundle.workflowExtension.workflow] = bundle
        }
    }

    func setDefaultWorkflow(_ workflow: SpinLabDomain.WorkflowKind) {
        withLock {
            fallbackKind = workflow
        }
    }

    func bundle(for workflow: SpinLabDomain.WorkflowKind) -> WorkflowBundle? {
        withLock {
            bundlesByKind[workflow]
        }
    }

    func defaultBundle() -> WorkflowBundle {
        if let existing = withLock({
            if let configured = bundlesByKind[fallbackKind] {
                return configured
            }
            return bundlesByKind.values.first
        }) {
            return existing
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
                workflowExtension: ThreeOmegaAHEWorkflowExtension(),
                metadataExtension: ThreeOmegaAHEMetadataExtension(),
                analysisModule: ThreeOmegaAHEAnalysisModuleExtension(),
                viewExtension: ThreeOmegaAHEViewExtension()
            )
        )
        register(
            WorkflowBundle(
                workflowExtension: XYRotationWorkflowExtension(),
                metadataExtension: XYRotationMetadataExtension(),
                analysisModule: XYRotationAnalysisModuleExtension(),
                viewExtension: XYRotationViewExtension()
            )
        )
        register(
            WorkflowBundle(
                workflowExtension: RSMWorkflowExtension(),
                metadataExtension: RSMMetadataExtension(),
                analysisModule: RSMAnalysisModuleExtension(),
                viewExtension: RSMViewExtension()
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

    private func withLock<T>(_ action: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return action()
    }
}
