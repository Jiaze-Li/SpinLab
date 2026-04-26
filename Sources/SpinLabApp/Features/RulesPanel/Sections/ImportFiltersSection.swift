import SwiftUI

struct ImportFiltersSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: ImportFiltersFileDraft?
    @State private var saveErrors: [RulesPanelFieldError] = []
    @State private var showConflictAlert = false
    @State private var pendingConflictChecksum = ""

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        VStack(spacing: 0) {
            saveBar()
            Divider()
            Group {
                if let d = draft {
                    scrollContent(d)
                } else {
                    ContentUnavailableView("No import filters loaded", systemImage: "doc.questionmark")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            saveBar()
        }
        .onAppear { syncFromStore() }
        .alert("External Change Detected", isPresented: $showConflictAlert) {
            Button("Reload External Changes") {
                store.reloadAfterExternalChange(section: .importFilters)
                syncFromStore()
            }
            Button("Override With My Edits", role: .destructive) {
                handleOutcome(store.overrideWithCurrentDraft(section: .importFilters))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file was modified externally (checksum: \(pendingConflictChecksum.prefix(8))). Choose how to resolve.")
        }
    }

    // MARK: - Save bar

    @ViewBuilder
    private func saveBar() -> some View {
        HStack(spacing: AppSpacing.md) {
            if !saveErrors.isEmpty {
                Text("\(saveErrors.count) validation error\(saveErrors.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Spacer()
            if let d = draft {
                Text("Schema version \(d.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Discard") { discardEdits() }
                .buttonStyle(.bordered)
                .disabled(!store.dirtySections.contains(.importFilters))
            Button("Save") { saveEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(!saveErrors.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(_ d: ImportFiltersFileDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                extensionListEditor(
                    title: "Supported Extensions",
                    subtitle: "Files with these extensions will be imported",
                    items: d.config.supportedFileExtensions,
                    onChange: { v in var u = d; u.config.supportedFileExtensions = v; apply(u) }
                )
                extensionListEditor(
                    title: "Ignored Extensions",
                    subtitle: "Files with these extensions will be skipped",
                    items: d.config.ignoredFileExtensions,
                    onChange: { v in var u = d; u.config.ignoredFileExtensions = v; apply(u) }
                )
                extensionErrorList()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    @ViewBuilder
    private func extensionListEditor(
        title: String,
        subtitle: String,
        items: [String],
        onChange: @escaping ([String]) -> Void
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Spacer()
                    Button("Add") { onChange(items + [""]) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                ForEach(items.indices, id: \.self) { idx in
                    HStack(spacing: AppSpacing.sm) {
                        TextField("e.g. csv", text: Binding(
                            get: { items[idx] },
                            set: { v in var updated = items; updated[idx] = v; onChange(updated) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        Button(role: .destructive) {
                            var updated = items; updated.remove(at: idx); onChange(updated)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove")
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(AppFontScale.groupHeader)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func extensionErrorList() -> some View {
        let errors = saveErrors
        if !errors.isEmpty {
            GroupBox("Validation Errors") {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(errors) { err in
                        Text("• \(err.message)")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func apply(_ d: ImportFiltersFileDraft) {
        draft = d
        store.updateImportFilters(d)
    }

    private func saveEdits() {
        store.selectSection(.importFilters)
        handleOutcome(store.saveCurrent())
    }

    private func discardEdits() {
        store.discardCurrent()
        syncFromStore()
        saveErrors = []
    }

    private func syncFromStore() {
        if let current = store.importFiltersDraft { draft = current }
    }

    private func handleOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved:
            saveErrors = []
        case .validationFailed(let errors):
            saveErrors = errors
        case .externalConflict(let checksum):
            pendingConflictChecksum = checksum
            showConflictAlert = true
        case .ioError(let error):
            saveErrors = [RulesPanelFieldError(field: "save", message: error.localizedDescription)]
        }
    }
}
