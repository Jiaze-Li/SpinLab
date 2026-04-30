import AppKit
import SwiftUI

struct RulesSectionShell<Content: View>: View {
    @Environment(SpinLabAppState.self) private var appState

    let section: RulesPanelSection
    let isDraftAvailable: Bool
    let versionLabel: String?
    let onSync: () -> Void
    let content: (Binding<[RulesPanelFieldError]>) -> Content

    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""
    @State private var shouldCloseAfterSave = false

    private var store: RulesManagementStore { appState.rulesPanel }

    init(
        section: RulesPanelSection,
        isDraftAvailable: Bool,
        versionLabel: String?,
        onSync: @escaping () -> Void,
        @ViewBuilder content: @escaping (Binding<[RulesPanelFieldError]>) -> Content
    ) {
        self.section = section
        self.isDraftAvailable = isDraftAvailable
        self.versionLabel = versionLabel
        self.onSync = onSync
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isDraftAvailable {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.xl) {
                            content($saveErrors)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.xl)
                    }
                } else {
                    ContentUnavailableView(
                        "No \(section.displayName.lowercased()) rules loaded",
                        systemImage: "doc.questionmark"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { onSync() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: section)
                onSync()
            }
            Button("Override With My Edits", role: .destructive) {
                handleOutcome(store.overrideWithCurrentDraft(section: section))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was modified externally (checksum: \(pendingConflictChecksum.prefix(8))). Choose how to resolve.")
        }
    }

    @ViewBuilder
    private func saveBar() -> some View {
        HStack(spacing: AppSpacing.md) {
            if !saveErrors.isEmpty {
                SaveErrorsBadge(errors: saveErrors)
            }
            Spacer()
            if let versionLabel {
                Text(versionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Apply") { applyEdits() }
                .buttonStyle(.bordered)
                .disabled(!saveErrors.isEmpty)
            Button("Discard") { discardEdits() }
                .buttonStyle(.bordered)
                .disabled(!store.dirtySections.contains(section))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    private func saveEdits() {
        store.selectSection(section)
        shouldCloseAfterSave = true
        handleOutcome(store.saveCurrent())
    }

    private func applyEdits() {
        store.selectSection(section)
        shouldCloseAfterSave = false
        handleOutcome(store.saveCurrent())
    }

    private func discardEdits() {
        store.discardCurrent()
        onSync()
        saveErrors = []
    }

    private func handleOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved, .savedWithMirrorWarning:
            saveErrors = []
            if shouldCloseAfterSave {
                NSApp.keyWindow?.close()
            }
            shouldCloseAfterSave = false
        case .validationFailed(let errors):
            saveErrors = errors
            shouldCloseAfterSave = false
        case .externalConflict(let checksum):
            pendingConflictChecksum = checksum
            showConflictAlert = true
        case .ioError(let error):
            saveErrors = [RulesPanelFieldError(field: "save", message: error.localizedDescription)]
            shouldCloseAfterSave = false
        }
    }
}
