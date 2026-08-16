import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.8 — cross-pane state ownership cleanup.
///
/// Guards the follow-up cleanup after the app-wide workspace rewrite: Inbox and
/// Library must share state through an explicit shared state/model owner, not
/// through a whole View-like struct held in `RootSplitView`'s `@State`. Also
/// guards deletion of Workbench forwarding residue (`WorkflowWorkspaceShell`,
/// `WorkflowWorkspaceProvider`, `WorkflowWorkspaceLoadPackPlacement`).
@Suite("V5.3.8 Cross-Pane State Ownership")
struct V538CrossPaneStateOwnershipTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot().appendingPathComponent(relativePath).path)
    }

    // MARK: - Inbox

    @Test("InboxWorkspaceHost no longer exists — Inbox shares InboxViewModel directly")
    func inboxWorkspaceHostIsGone() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Inbox/InboxView.swift")
        #expect(!source.contains("struct InboxWorkspaceHost"))
        #expect(source.contains("struct InboxPrimaryView"))
    }

    @Test("RootSplitView owns one InboxViewModel instance shared by Primary and Detail")
    func rootOwnsSharedInboxViewModel() throws {
        let root = try loadSource("Sources/SpinLabApp/App/RootSplitView.swift")
        #expect(root.contains("@State private var inboxViewModel = InboxViewModel()"))
        #expect(root.contains("AppPrimaryContent(inboxViewModel: inboxViewModel"))
    }

    @Test("AppPrimaryContent/AppDetailContent take InboxViewModel directly, not a host View")
    func appContentTakesInboxViewModelDirectly() throws {
        let primary = try loadSource("Sources/SpinLabApp/App/AppPrimaryContent.swift")
        let detail = try loadSource("Sources/SpinLabApp/App/AppDetailContent.swift")
        #expect(primary.contains("let inboxViewModel: InboxViewModel"))
        #expect(!primary.contains("InboxWorkspaceHost"))
        #expect(!detail.contains("InboxWorkspaceHost"))
    }

    // MARK: - Library

    @Test("LibraryView no longer exists — Library shares LibraryWorkspaceState directly")
    func libraryViewIsGone() throws {
        #expect(!fileExists("Sources/SpinLabApp/Features/Library/LibraryView.swift"))
        #expect(!fileExists("Sources/SpinLabApp/Features/Library/LibraryView+DetailColumn.swift"))
        #expect(fileExists("Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift"))
        #expect(fileExists("Sources/SpinLabApp/Features/Library/LibraryDetailView.swift"))
        #expect(fileExists("Sources/SpinLabApp/Features/Library/LibraryWorkspaceState.swift"))
    }

    @Test("RootSplitView owns one LibraryWorkspaceState instance shared by Primary and Detail")
    func rootOwnsSharedLibraryState() throws {
        let root = try loadSource("Sources/SpinLabApp/App/RootSplitView.swift")
        #expect(root.contains("@State private var libraryState = LibraryWorkspaceState()"))
        #expect(root.contains("AppPrimaryContent(inboxViewModel: inboxViewModel, libraryState: libraryState)"))
        #expect(root.contains("AppDetailContent(libraryState: libraryState)"))
    }

    @Test("AppPrimaryContent/AppDetailContent take LibraryWorkspaceState directly, not a whole LibraryView")
    func appContentTakesLibraryStateDirectly() throws {
        let primary = try loadSource("Sources/SpinLabApp/App/AppPrimaryContent.swift")
        let detail = try loadSource("Sources/SpinLabApp/App/AppDetailContent.swift")
        #expect(primary.contains("let libraryState: LibraryWorkspaceState"))
        #expect(detail.contains("let libraryState: LibraryWorkspaceState"))
        #expect(!primary.contains(": LibraryView"))
        #expect(!detail.contains(": LibraryView"))
    }

    @Test("LibraryWorkspaceState is an @Observable reference type, not a View")
    func libraryWorkspaceStateIsObservableClass() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Library/LibraryWorkspaceState.swift")
        #expect(source.contains("@Observable"))
        #expect(source.contains("final class LibraryWorkspaceState"))
    }

    @Test("Primary and Detail both bind the same LibraryWorkspaceState instance")
    func primaryAndDetailBindSameState() throws {
        let primary = try loadSource("Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift")
        let detail = try loadSource("Sources/SpinLabApp/Features/Library/LibraryDetailView.swift")
        #expect(primary.contains("@Bindable var state: LibraryWorkspaceState"))
        #expect(detail.contains("@Bindable var state: LibraryWorkspaceState"))
    }

    @Test("Detail-rendered disclosure state lives on the shared model, not local @State")
    func detailDisclosureStateIsShared() throws {
        let detail = try loadSource("Sources/SpinLabApp/Features/Library/LibraryDetailView.swift")
        #expect(!detail.contains("@State var isMetadataSectionExpanded"))
        #expect(!detail.contains("@State var expandedWorkflows"))
        #expect(detail.contains("$state.isMetadataSectionExpanded"))
        #expect(detail.contains("$state.expandedWorkflows"))
    }

    // MARK: - Workbench forwarding residue

    @Test("WorkflowWorkspaceShell no longer exists")
    func workflowWorkspaceShellIsGone() throws {
        #expect(!fileExists("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift"))
    }

    @Test("WorkflowWorkspaceProvider marker protocol no longer exists")
    func workflowWorkspaceProviderIsGone() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift")
        #expect(!source.contains("protocol WorkflowWorkspaceProvider"))
        // The file still hosts WorkbenchWorkspaceProviding and friends.
        #expect(source.contains("protocol WorkbenchWorkspaceProviding"))
    }

    @Test("WorkflowWorkspaceLoadPackPlacement no longer exists — ActionBar constructs the popover directly")
    func workflowWorkspaceLoadPackPlacementIsGone() throws {
        #expect(!fileExists("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceLoadPackPlacement.swift"))
        let actionBar = try loadSource("Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift")
        #expect(actionBar.contains("WorkbenchLoadPackPopover(workflowID: workflowID, store: store)"))
    }

    @Test("Workflow views construct WorkflowWorkspaceLeftColumn directly, not through a shell")
    func workflowViewsUseLeftColumnDirectly() throws {
        for file in [
            "AHEWorkspaceView.swift",
            "IVWorkspaceView.swift",
            "ThreeOmegaWorkspaceView.swift",
            "XYRotationWorkspaceView.swift",
            "RTWorkspaceView.swift",
            "RSMWorkspaceView.swift",
        ] {
            let source = try loadSource("Sources/SpinLabApp/Features/Workbench/\(file)")
            #expect(source.contains("WorkflowWorkspaceLeftColumn("), "\(file) must construct WorkflowWorkspaceLeftColumn directly")
            #expect(!source.contains("WorkflowWorkspaceShell"), "\(file) must not reference WorkflowWorkspaceShell")
            #expect(!source.contains("WorkflowWorkspaceProvider"), "\(file) must not conform to the deleted marker protocol")
        }
    }
}
