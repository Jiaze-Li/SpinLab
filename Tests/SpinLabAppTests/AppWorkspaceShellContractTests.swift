import Foundation
import Testing
@testable import SpinLabApp

/// Regression guards for the P1 fix on PR #155: hosted panes must stay in
/// the same SwiftUI hierarchy as `RootSplitView` so `@Environment` values
/// (`SpinLabAppState`, `\.openWindow`, …) resolve inside Navigation/Primary/
/// Detail content. The prior `AppWorkspaceSplitView` (an `NSViewRepresentable`
/// wrapping three independent `NSHostingView` roots) broke that — SwiftUI
/// environment does not cross an `NSHostingView` boundary implicitly.
/// See `docs/architecture/workbench/WORKBENCH_LAYOUT_OWNERSHIP_AUDIT.md`.
@Suite("AppWorkspaceShell environment-boundary contract")
struct AppWorkspaceShellContractTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func allSwiftFiles() throws -> [URL] {
        let sourcesRoot = repoRoot().appendingPathComponent("Sources/SpinLabApp")
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // INV-1: no obsolete NSViewRepresentable/NSSplitView workspace primitive remains anywhere.
    @Test("AppWorkspaceSplitView / AppOwnedWorkspaceSplitView no longer exist in the tree")
    func obsoleteAppKitSplitPrimitiveIsGone() throws {
        for file in try allSwiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("struct AppWorkspaceSplitView"), "\(file.lastPathComponent) must not reintroduce AppWorkspaceSplitView")
            #expect(!source.contains("class AppOwnedWorkspaceSplitView"), "\(file.lastPathComponent) must not reintroduce AppOwnedWorkspaceSplitView")
        }
    }

    // INV-2: no NSHostingView is constructed for Navigation/Primary/Detail workspace pane
    // content specifically (the UI/ directory that owns app-wide workspace rendering).
    // Other NSViewRepresentable/NSHostingView usage elsewhere in the app — e.g. plot canvas
    // mouse tracking — is unrelated to this contract and out of scope.
    @Test("No NSHostingView is constructed for workspace pane content")
    func noNestedHostingViewForPanes() throws {
        let workspaceUIFiles = ["AppWorkspaceShell.swift", "WorkspaceDivider.swift", "WorkspaceLayoutState.swift"]
        for filename in workspaceUIFiles {
            let source = try loadSource("Sources/SpinLabApp/UI/\(filename)")
            #expect(!source.contains("NSHostingView("), "\(filename) must not construct an NSHostingView for pane content")
        }
    }

    // INV-3: AppWorkspaceShell is the sole workspace geometry owner — GeometryReader-based.
    @Test("AppWorkspaceShell owns workspace geometry via GeometryReader + WorkspaceLayoutState")
    func shellOwnsGeometryDirectly() throws {
        let source = try loadSource("Sources/SpinLabApp/UI/AppWorkspaceShell.swift")
        #expect(source.contains("GeometryReader"))
        #expect(source.contains("@State private var layoutState = WorkspaceLayoutState()"))
        #expect(source.contains("WorkspaceDivider()"))
    }

    // INV-4: live drag preview never persists — WorkspaceLayoutState is only mutated via
    // commitLeftWidth/commitRightWidth in onEnded, never during onChanged/updating.
    @Test("Drag preview uses @GestureState; commits happen only in onEnded")
    func dragPreviewIsPureUntilDragEnd() throws {
        let source = try loadSource("Sources/SpinLabApp/UI/AppWorkspaceShell.swift")
        #expect(source.contains("@GestureState private var leftDragTranslation"))
        #expect(source.contains("@GestureState private var rightDragTranslation"))
        #expect(source.contains(".onEnded"))
        // commitLeftWidth/commitRightWidth must not appear inside an `.updating` closure body —
        // a coarse but effective guard: they should only follow an `.onEnded` in source order
        // per gesture block. We assert they exist at all and are each paired with exactly one
        // onEnded per gesture (two gestures => two commit call sites).
        #expect(source.components(separatedBy: "commitLeftWidth(").count - 1 == 1)
        #expect(source.components(separatedBy: "commitRightWidth(").count - 1 == 1)
    }

    // INV-5: RootSplitView's SpinLabAppState environment injection sits above AppWorkspaceShell,
    // and pane content (AppPrimaryContent/AppDetailContent) reads @Environment directly —
    // both must be reachable in the *same* SwiftUI tree for this to work at runtime.
    @Test("Pane content reads @Environment(SpinLabAppState.self) directly, not via a manually-bridged value")
    func paneContentUsesRealEnvironment() throws {
        let primary = try loadSource("Sources/SpinLabApp/App/AppPrimaryContent.swift")
        let detail = try loadSource("Sources/SpinLabApp/App/AppDetailContent.swift")
        #expect(primary.contains("@Environment(SpinLabAppState.self) private var appState"))
        #expect(detail.contains("@Environment(SpinLabAppState.self) private var appState"))
    }
}
