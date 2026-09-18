import SwiftUI

@main
struct SpinLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: SpinLabAppState

    init() {
        let bundle = WorkflowRegistry.shared.defaultBundle()
        let rulesBookSettings = RulesBookSettings()
        // Must run before AppEnvironment.live(): that factory constructs rule-dependent
        // production objects (registry indexing, substrate rule lookups) that must derive
        // from the configured Rule Book, not an unconfigured/fallback RuleLoader.
        rulesBookSettings.prepareAndConfigureRuleLoader()
        let environment = AppEnvironment.live()
        _appState = State(initialValue: SpinLabAppState(
            workflowBundle: bundle,
            environment: environment,
            rulesBookSettings: rulesBookSettings
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 520)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        appState.flushInteractionSnapshotNow(source: "scenePhaseInactive")
                    }
                }
        }
        .windowStyle(.titleBar)

        Window("Rules", id: "spin-rules") {
            RulesPanelView()
                .environment(appState)
        }

        Window("Recompute Preview", id: "recompute-preview") {
            RecomputePreviewPanel(library: appState.library)
        }
        .defaultSize(width: 900, height: 600)
    }

}
