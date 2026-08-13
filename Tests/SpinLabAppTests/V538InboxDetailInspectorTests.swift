import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.8 — Inbox Detail / Inspector resolution.
///
/// Before this pass, Inbox Detail always rendered a static `InboxInspectorReservedPanel`
/// placeholder, while a fully-implemented `InboxInspectorPanel` (file summary, routing
/// summary, warnings) sat in the codebase with zero runtime call sites. This wires the real
/// inspector into Detail, driven by the same `appState.selectedPendingImport` identity
/// Primary (`InboxOperationPanel`'s List selection) already owns — no second Inbox state
/// model, no new selection/routing/import behavior.
@Suite("V5.3.8 Inbox Detail Inspector")
struct V538InboxDetailInspectorTests {

    private func loadSource(_ relativePath: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: base.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("AppDetailContent.swift routes the Inbox area to InboxDetailView")
    func detailContentRoutesToInboxDetailView() throws {
        let source = try loadSource("Sources/SpinLabApp/App/AppDetailContent.swift")
        #expect(source.contains("case .inbox:"))
        #expect(source.contains("InboxDetailView()"),
                "Inbox Detail must render the real InboxDetailView, not a placeholder")
        #expect(!source.contains("InboxInspectorReservedPanel"),
                "the obsolete always-placeholder panel must not be referenced")
    }

    @Test("InboxInspectorReservedPanel type no longer exists anywhere in production source")
    func reservedPlaceholderTypeIsGone() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = base.appendingPathComponent("Sources/SpinLabApp")
        let allFiles = try FileManager.default
            .subpathsOfDirectory(atPath: sourcesRoot.path)
            .filter { $0.hasSuffix(".swift") }

        var filesDefiningReservedPanel: [String] = []
        for relativePath in allFiles {
            let src = try String(contentsOf: sourcesRoot.appendingPathComponent(relativePath), encoding: .utf8)
            if src.contains("struct InboxInspectorReservedPanel") {
                filesDefiningReservedPanel.append(relativePath)
            }
        }
        #expect(filesDefiningReservedPanel.isEmpty,
                "InboxInspectorReservedPanel must stay deleted now that InboxInspectorPanel is wired in; found in: \(filesDefiningReservedPanel)")
    }

    @Test("InboxDetailView.swift renders the real inspector for the selected pending import, and a distinct empty state otherwise")
    func detailViewBranchesOnSelection() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Inbox/InboxDetailView.swift")
        #expect(source.contains("appState.selectedPendingImport"),
                "InboxDetailView must read the same selectedPendingImport identity Primary drives")
        #expect(source.contains("InboxInspectorPanel(pending: pending)"),
                "InboxDetailView must mount the real inspector when a pending import is selected")
        #expect(source.contains("InboxInspectorEmptyState"),
                "InboxDetailView must show a dedicated empty state when nothing is selected")
    }

    @Test("Inbox Detail and Primary share the same selection identity — no second Inbox state model")
    func detailAndPrimaryShareSelectionIdentity() throws {
        let detailSource = try loadSource("Sources/SpinLabApp/Features/Inbox/InboxDetailView.swift")
        let primarySource = try loadSource("Sources/SpinLabApp/Features/Inbox/InboxOperationPanel.swift")
        #expect(detailSource.contains("appState.selectedPendingImport"))
        #expect(primarySource.contains("appState.selectedPendingImport") || primarySource.contains("selectedPendingImportID"),
                "Primary must drive the same selectedPendingImport(ID) identity Detail reads")
        // Guard against a second Inbox view model / selection store appearing alongside
        // InboxViewModel + InboxFeatureStore.
        #expect(!detailSource.contains("@State") && !detailSource.contains("@Observable"),
                "InboxDetailView must not own any state of its own — it only renders off shared Inbox state")
    }

    @Test("InboxInspectorPanel.swift consumes existing, current Inbox routing/warning APIs — no new business behavior")
    func inspectorPanelUsesExistingAPIsOnly() throws {
        let source = try loadSource("Sources/SpinLabApp/Features/Inbox/InboxInspectorPanel.swift")
        #expect(source.contains("appState.pendingRoutingSnapshot(for: pending)"))
        #expect(source.contains("appState.pendingDisplayWarningItems(for: pending)"))
        #expect(!source.contains("struct InboxInspectorReservedPanel"),
                "the reserved placeholder must not still be defined in this file")
    }

    @MainActor
    @Test("SpinLabAppState exposes selectedPendingImport as a live projection of selectedPendingImportID, not separate state")
    func selectedPendingImportIsProjection() throws {
        let source = try loadSource("Sources/SpinLabApp/App/SpinLabAppState+RoutingPresentation.swift")
        #expect(source.contains("var selectedPendingImport: SpinLabDomain.PendingImport?"))
        #expect(source.contains("inboxFeatureStore.pendingImports.first { $0.id == selectedPendingImportID }"),
                "selectedPendingImport must be derived from selectedPendingImportID + pendingImports, not stored independently")
    }
}
