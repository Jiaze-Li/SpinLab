import SwiftUI

@main
struct SpinLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: SpinLabAppState

    init() {
        // First thing at launch, before any live service exists: resolve isolated
        // test mode. A bad or incomplete isolated configuration terminates here,
        // before any production data is read or written.
        let launchArguments = CommandLine.arguments
        if case let .failure(refusal) = IsolatedLaunch.bootstrap(
            arguments: launchArguments,
            environment: ProcessInfo.processInfo.environment
        ) {
            fputs("SpinLab refused to start in isolated test mode: \(refusal)\n", stderr)
            exit(IsolatedLaunch.refusalExitCode)
        }
        let bundle = WorkflowRegistry.shared.defaultBundle()
        let rulesBookSettings = RulesBookSettings()
        // Must run before AppEnvironment.live(): that factory constructs rule-dependent
        // production objects (registry indexing, substrate rule lookups) that must derive
        // from the configured Rule Book, not an unconfigured/fallback RuleLoader.
        rulesBookSettings.prepareAndConfigureRuleLoader()
        let environment = AppEnvironment.live()
        let state = SpinLabAppState(
            workflowBundle: bundle,
            environment: environment,
            rulesBookSettings: rulesBookSettings
        )
        _appState = State(initialValue: state)
        if launchArguments.contains(IsolatedLaunch.selfTestArgument) {
            IsolatedLaunch.runSelfTestAndExit(appState: state)
        }
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
