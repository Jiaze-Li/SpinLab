import SwiftUI

@main
struct SpinLabApp: App {
    @StateObject private var appState: SpinLabAppState

    init() {
        let registry = WorkflowRegistry.shared
        let workflow = Self.workflowSelection(from: ProcessInfo.processInfo.environment["SPINLAB_WORKFLOW"])
        let bundle = registry.bundle(for: workflow) ?? registry.defaultBundle()
        _appState = StateObject(
            wrappedValue: SpinLabAppState(workflowBundle: bundle)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environmentObject(appState)
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
