import SwiftUI

/// Management's right column. Defaults to a light Library Overview built only
/// from state the management page already shows; switches to the existing
/// read-only Sample Preview only after an explicit Registry Preview pick.
@MainActor
struct LibraryManagementDetailView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Bindable var state: LibraryWorkspaceState

    private var lib: LibraryFeatureStore { appState.library }

    /// Preview is read-only by construction: it requires Browser focus, and
    /// every Detail mutation is gated on Drawer focus.
    private var showsRegistryPreview: Bool {
        lib.isManagementPreviewActive
            && lib.libraryActiveSelectionSource == .browser
            && state.selectedSample(appState) != nil
    }

    var body: some View {
        if showsRegistryPreview {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        lib.isManagementPreviewActive = false
                    } label: {
                        Label("Back to Overview", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.bordered)
                    Text("Registry Preview (read-only)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                LibraryDetailView(state: state)
            }
        } else {
            LibraryOverviewView()
        }
    }
}

/// Lightweight overview: reuses existing trusted status only (no new scans).
struct LibraryOverviewView: View {
    @Environment(SpinLabAppState.self) private var appState

    private var lib: LibraryFeatureStore { appState.library }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library Overview")
                        .font(AppFontScale.sectionTitle)
                    Spacer()
                    Text(AppVersion.current)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                overviewGroup("Library Root") {
                    MetadataValueRow(label: "Path", value: lib.librarySettings.rootPath ?? "Not set", monospaced: true)
                    statusLine(lib.libraryRootVerificationMessage)
                }

                overviewGroup("Backup") {
                    MetadataValueRow(label: "Path", value: lib.librarySettings.backupPath ?? "Not set", monospaced: true)
                    statusLine(lib.libraryBackupError, isError: true)
                    statusLine(lib.libraryBackupError == nil ? lib.libraryBackupMessage : nil)
                }

                overviewGroup("Registry") {
                    MetadataValueRow(label: "Source", value: lib.librarySettings.registrySourcePath ?? "Not loaded", monospaced: true)
                    statusLine(lib.librarySyncStatusMessage)
                    if let review = lib.libraryRefreshReview {
                        Text("Pending: \(review.newSamples.count) new, \(review.changedSamples.count) changed, \(review.removedSamples.count) removed")
                            .font(.callout)
                    }
                    statusLine(lib.libraryPreviewMessage)
                }

                overviewGroup("Audit & Warnings") {
                    if lib.libraryPreviewWarnings.isEmpty {
                        Text("No registry warnings")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(lib.libraryPreviewWarnings.count) registry warning(s)")
                            .font(.callout)
                        ForEach(lib.libraryPreviewWarnings) { warning in
                            Text(warning.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    statusLine(lib.chartAuditMessage)
                }

                Text("Select a sample in Registry Preview to inspect it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
        }
    }

    private func overviewGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title).font(AppFontScale.groupHeader)
        }
    }

    @ViewBuilder
    private func statusLine(_ text: String?, isError: Bool = false) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.callout)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .textSelection(.enabled)
        }
    }
}
