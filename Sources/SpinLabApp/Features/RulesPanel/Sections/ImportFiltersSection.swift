import SwiftUI

struct ImportFiltersSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: ImportFiltersFileDraft?

    private var store: RulesManagementStore { appState.rulesPanel }

    var body: some View {
        RulesSectionShell(
            section: .importFilters,
            isDraftAvailable: draft != nil,
            versionLabel: draft.map { "Schema version \($0.version)" },
            onSync: syncFromStore
        ) { $saveErrors in
            if let d = draft {
                scrollContent(d, saveErrors: $saveErrors)
            }
        }
    }

    // MARK: - Scroll content

    @ViewBuilder
    private func scrollContent(_ d: ImportFiltersFileDraft, saveErrors: Binding<[RulesPanelFieldError]>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                extensionListEditor(
                    title: "Supported Extensions",
                    subtitle: "Files with these extensions will be imported",
                    items: d.config.supportedFileExtensions,
                    onChange: { v in var u = d; u.config.supportedFileExtensions = v; apply(u) }
                )
                .errorHighlight(saveErrors.wrappedValue.hasGroup("extensions"))
                extensionListEditor(
                    title: "Ignored Extensions",
                    subtitle: "Files with these extensions will be skipped",
                    items: d.config.ignoredFileExtensions,
                    onChange: { v in var u = d; u.config.ignoredFileExtensions = v; apply(u) }
                )
                .errorHighlight(saveErrors.wrappedValue.hasGroup("extensions"))
                extensionErrorList(saveErrors.wrappedValue)
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
    private func extensionErrorList(_ errors: [RulesPanelFieldError]) -> some View {
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

    private func syncFromStore() {
        if let current = store.importFiltersDraft { draft = current }
    }
}
