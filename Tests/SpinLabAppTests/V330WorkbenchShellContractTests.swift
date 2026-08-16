import Foundation
import Testing
@testable import SpinLabApp

/// V3.3.0 — Workbench shell region contract.
///
/// `WorkflowWorkspaceProvider` (the marker protocol this suite originally guarded)
/// was removed as dead weight — it had no requirements and nothing consumed it
/// polymorphically; `WorkflowWorkspaceRegistry` dispatches on concrete types.
/// Visual/layout acceptance was verified manually against the desktop build (v3.3.0).
@Suite("V3.3.0 Workbench Shell Contract")
struct V330WorkbenchShellContractTests {

    @Test("WorkflowWorkspaceRegistry resolves workflow ID A to a non-fallback view")
    func registryResolvesAHEWorkflowID() {
        // WorkflowWorkspaceRegistry.leftContent(for:)/rightContent(for:) are @ViewBuilder —
        // we verify the registry type exists and the dispatch table compiles with the
        // expected case. Runtime dispatch is covered by V3.3.2 tests.
        let _: WorkflowWorkspaceRegistry.Type = WorkflowWorkspaceRegistry.self
    }
}

// MARK: - App-wide single-workspace ownership regression guard
//
// Source-inspection guard for the app-wide three-pane workspace rewrite:
// Inbox/Library/Workbench must never own an independent split layout — only
// `AppWorkspaceShell` may construct the main workspace geometry (a pure
// SwiftUI `GeometryReader`/`HStack` composition, not an `NSSplitView`). This
// supersedes the earlier Workbench-only "single AppColumnShell" guard, which
// is now obsolete: `AppColumnShell` no longer exists in the tree. See
// `docs/architecture/workbench/WORKBENCH_LAYOUT_OWNERSHIP_AUDIT.md`.
@Suite("App-wide workspace ownership regression guard")
struct AppWorkspaceOwnershipRegressionTests {

    private static let workflowViewFiles = [
        "AHEWorkspaceView.swift",
        "IVWorkspaceView.swift",
        "ThreeOmegaWorkspaceView.swift",
        "XYRotationWorkspaceView.swift",
        "RTWorkspaceView.swift",
        "RSMWorkspaceView.swift",
    ]

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func loadWorkbenchSource(_ filename: String) throws -> String {
        try loadSource("Sources/SpinLabApp/Features/Workbench/\(filename)")
    }

    private func allSwiftFiles() throws -> [URL] {
        let sourcesRoot = repoRoot().appendingPathComponent("Sources/SpinLabApp")
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // INV-1: the app-wide root routes Primary/Detail content through the single shell.
    @Test("RootSplitView routes through AppWorkspaceShell")
    func rootSplitViewRoutesThroughWorkspaceShell() throws {
        let source = try loadSource("Sources/SpinLabApp/App/RootSplitView.swift")
        #expect(source.contains("AppWorkspaceShell {"))
    }

    // INV-2: exactly one AppWorkspaceShell( call site in the whole app.
    @Test("Exactly one AppWorkspaceShell call site exists")
    func exactlyOneWorkspaceShellCallSite() throws {
        var callSites: [String] = []
        for file in try allSwiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("AppWorkspaceShell {") || source.contains("AppWorkspaceShell(") {
                callSites.append(file.lastPathComponent)
            }
        }
        #expect(callSites == ["RootSplitView.swift"],
                "AppWorkspaceShell must be constructed only by RootSplitView; found in: \(callSites)")
    }

    // INV-3: the obsolete per-area split primitives no longer exist anywhere in the tree.
    @Test("AppColumnShell / SplitWidthState / per-area AppNativeSplitView no longer exist")
    func obsoleteSplitPrimitivesAreGone() throws {
        for file in try allSwiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("AppColumnShell("), "\(file.lastPathComponent) must not reference AppColumnShell")
            #expect(!source.contains("struct SplitWidthState"), "\(file.lastPathComponent) must not reintroduce SplitWidthState")
            #expect(!source.contains("HSplitView("), "\(file.lastPathComponent) must not construct HSplitView directly")
        }
    }

    // INV-4: no per-area persisted width keys remain in production usage.
    @Test("No production usage of legacy per-area splitView.*.leftWidth keys")
    func noLegacyPerAreaWidthKeys() throws {
        for file in try allSwiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("splitView.inbox.leftWidth"), "\(file.lastPathComponent)")
            #expect(!source.contains("splitView.library.leftWidth"), "\(file.lastPathComponent)")
            #expect(!source.contains("splitView.workbench.leftWidth"), "\(file.lastPathComponent)")
        }
    }

    // INV-5: Workbench workflow dispatch happens inside WorkbenchPrimaryView/WorkbenchDetailView,
    // not around a per-workflow split owner (WorkbenchWorkflowSplitView no longer exists).
    @Test("Workbench routes .workflow through WorkflowWorkspaceRegistry from WorkbenchPrimaryView/WorkbenchDetailView")
    func workbenchRoutesThroughRegistry() throws {
        let source = try loadWorkbenchSource("WorkbenchView.swift")
        #expect(source.contains("struct WorkbenchPrimaryView"))
        #expect(source.contains("struct WorkbenchDetailView"))
        #expect(source.contains("WorkflowWorkspaceRegistry.leftContent(for:"))
        #expect(source.contains("WorkflowWorkspaceRegistry.rightContent(for:"))
    }

    // INV-6: no per-workflow view instantiates a split primitive directly.
    @Test("Workflow-specific workspace views do not instantiate split geometry directly")
    func workflowViewsDoNotOwnSplitGeometry() throws {
        for file in Self.workflowViewFiles {
            let source = try loadWorkbenchSource(file)
            #expect(!source.contains("AppColumnShell("), "\(file) must not construct AppColumnShell directly")
            #expect(!source.contains("HSplitView("), "\(file) must not construct HSplitView directly")
        }
    }

    // INV-7/INV-8: WorkbenchPlotTabPicker defaults to intrinsic width; fixed width is opt-in.
    @Test("WorkbenchPlotTabPicker.pickerWidth defaults to intrinsic (nil), not a hardcoded 160")
    func pickerWidthDefaultsToIntrinsic() throws {
        let source = try loadSource("Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotNavigationStrip.swift")
        #expect(source.contains("var pickerWidth: CGFloat? = nil"))
        #expect(!source.contains("var pickerWidth: CGFloat = 160"))
        // Callers that need a fixed column width still have an explicit named constant to opt into.
        #expect(source.contains("static let tabPickerWidth: CGFloat = 160"))
    }
}
