import SwiftUI

@main
struct SpinLabApp: App {
    @StateObject private var appState = SpinLabAppState()

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}
