import SwiftUI

/// The single app-wide three-pane workspace composition
/// (Navigation | Primary | Detail).
///
/// This is the only place in the app that owns a main workspace
/// `NSSplitView`. Inbox, Library, and Workbench never construct their own —
/// they only supply content into `primary`/`detail`. The shell, its
/// `NSSplitView`, and its three hosting views stay alive across Inbox ↔
/// Library ↔ Workbench route changes and Workbench workflow switches;
/// branch *inside* `primary`/`detail` rather than around this call site.
struct AppWorkspaceShell<Navigation: View, Primary: View, Detail: View>: View {
    @ViewBuilder var navigation: () -> Navigation
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var detail: () -> Detail

    @State private var layoutState = WorkspaceLayoutState()

    var body: some View {
        AppWorkspaceSplitView(layoutState: layoutState, navigation: navigation(), primary: primary(), detail: detail())
    }
}
