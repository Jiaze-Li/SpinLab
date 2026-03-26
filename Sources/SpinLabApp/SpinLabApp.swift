import SwiftUI

@main
struct SpinLabApp: App {
    @State private var appState: SpinLabAppState

    init() {
        let registry = WorkflowRegistry.shared
        let workflow = Self.workflowSelection(from: ProcessInfo.processInfo.environment["SPINLAB_WORKFLOW"])
        let bundle = registry.bundle(for: workflow) ?? registry.defaultBundle()
        let environment = AppEnvironment.live()
        _appState = State(initialValue: SpinLabAppState(workflowBundle: bundle, environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }

    private static func workflowSelection(from rawValue: String?) -> SpinLabDomain.WorkflowKind {
        guard let rawValue else {
            return .amrPhe
        }
        switch rawValue.lowercased() {
        case "dummy":
            return .dummy
        default:
            return .amrPhe
        }
    }
}
