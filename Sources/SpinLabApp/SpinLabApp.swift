import SwiftUI

@main
struct SpinLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: SpinLabAppState

    init() {
        RulesMigration.runIfNeeded()
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
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        appState.flushInteractionSnapshotNow()
                    }
                }
        }
        .windowStyle(.titleBar)

        Window("Rules", id: "spin-rules") {
            RulesPanelView()
                .environment(appState)
        }
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
