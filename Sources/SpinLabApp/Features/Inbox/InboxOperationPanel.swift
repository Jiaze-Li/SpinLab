import AppKit
import SwiftUI

struct InboxOperationPanel: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let inboxViewModel: InboxViewModel
    @Binding var isPendingQueueExpanded: Bool
    let applySelected: () -> Void
    let applyAll: () -> Void
    @State private var isPresentingClearImportsConfirm = false

    var body: some View {
        @Bindable var bindableInbox = appState.inbox
        let projection = inboxViewModel.projection(from: appState)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Inbox Operations")
                        .font(AppFontScale.sectionTitle)
                    Button("Rules") { openWindow(id: "spin-rules") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                    Text(AppVersion.current)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                operationBox("File", isExpanded: $isPendingQueueExpanded) {
                    GroupBox("Actions") {
                        HStack(spacing: 10) {
                            Button("Import Files") {
                                print("[PERF][inbox] importFiles clicked")
                                presentMeasurementImportPanel()
                            }

                            Button("Recompute Route") {
                                appState.recomputeAllPendingParsedHints()
                            }
                            .disabled(appState.inbox.pendingImports.isEmpty)

                            Button("Clear Imports", role: .destructive) {
                                isPresentingClearImportsConfirm = true
                            }
                            .disabled(appState.inbox.pendingImports.isEmpty)

                            Button("Clear Selected", role: .destructive) {
                                appState.clearSelectedPendingImport()
                            }
                            .disabled(appState.selectedPendingImport == nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Pending Queue") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                queueStatusCard(
                                    title: "Pending",
                                    count: appState.inbox.pendingImports.count,
                                    tint: .secondary,
                                    filter: .all
                                )
                                queueStatusCard(
                                    title: "Library Matched",
                                    count: projection.libraryMatchedCount,
                                    tint: .green,
                                    filter: .libraryMatched
                                )
                                queueStatusCard(
                                    title: "Review Required",
                                    count: projection.reviewRequiredCount,
                                    tint: .orange,
                                    filter: .reviewRequired
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let selected = appState.selectedPendingImport {
                                MetadataValueRow(label: "File Path", value: selected.sourceFilePath, monospaced: true)
                            }

                            if projection.filteredPendingImports.isEmpty {
                                Text("No pending files for this filter.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                List(projection.filteredPendingImports, selection: $bindableInbox.selectedPendingImportID) { pending in
                                    let presentation = projection.routePresentationByID[pending.id]
                                    let verdict = presentation?.verdict ?? .reviewRequired
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pending.fileName)
                                            .font(.headline)
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(pending.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Route: \(presentation?.routeStatusTitle ?? verdict.displayTitle)")
                                            .font(.caption)
                                            .foregroundStyle(verdict == .libraryMatched ? .green : .orange)
                                        if appState.hasSavedRoutingDraft(for: pending) {
                                            Text("Routing draft: saved")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .frame(minHeight: 210, maxHeight: 360)
                                .listStyle(.inset)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }

                    GroupBox("Selection Workbench") {
                        if let pending = appState.selectedPendingImport {
                            InboxSelectionWorkbenchPanel(
                                pending: pending,
                                applySelected: applySelected,
                                applyAll: applyAll
                            )
                                .id(pending.id)
                        } else {
                            Text("Select one pending file to edit and save confirmation draft.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .confirmationDialog(
            "Clear Imports?",
            isPresented: $isPresentingClearImportsConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Pending Imports", role: .destructive) {
                appState.clearPendingImports()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears pending queue items and unarchived temporary imports only. Archived library drawers are unchanged.")
        }
    }

    private func presentMeasurementImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.title = "Import Measurement Files"
        panel.message = "Choose measurement files or folders. Folders are scanned recursively."

        print("[PERF][inbox] importFiles sheet open")
        if panel.runModal() == .OK {
            appState.importFiles(from: panel.urls)
        }
    }

    @ViewBuilder
    private func queueStatusCard(title: String, count: Int, tint: Color, filter: InboxViewModel.FileFilter) -> some View {
        let isSelected = inboxViewModel.fileFilter == filter

        Button {
            inboxViewModel.fileFilter = filter
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.22) : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tint : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func operationBox(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CollapsibleSectionHeader(title: title, isExpanded: isExpanded)

            if isExpanded.wrappedValue {
                GroupBox {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
