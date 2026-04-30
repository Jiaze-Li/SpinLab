import SwiftUI

struct FilenameTokenizationSection: View {
    @Environment(SpinLabAppState.self) private var appState

    @State private var draft: FilenameTokenizationFileDraft?

    private var store: RulesManagementStore { appState.rulesPanel }
    private let allowedSources = ["file", "parent", "grandparent"]

    var body: some View {
        RulesSectionShell(
            section: .filenameTokenization,
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
    private func scrollContent(_ d: FilenameTokenizationFileDraft, saveErrors: Binding<[RulesPanelFieldError]>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                tokenizationGroup(d)
                    .errorHighlight(saveErrors.wrappedValue.hasGroup("tokenization.separators"))
                sourcesGroup(d)
                    .errorHighlight(saveErrors.wrappedValue.hasGroup("sources"))
                channelGroup(d)
                    .errorHighlight(saveErrors.wrappedValue.hasGroup("channel.aliases"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Tokenization

    @ViewBuilder
    private func tokenizationGroup(_ d: FilenameTokenizationFileDraft) -> some View {
        GroupBox("Tokenization") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                LabeledContent("Separators") {
                    TextField("e.g. _- ()", text: Binding(
                        get: { d.tokenization.separators },
                        set: { v in var u = d; u.tokenization.separators = v; apply(u) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .font(.body.monospaced())
                }
                LabeledContent("Case Fold") {
                    Picker("", selection: Binding(
                        get: { d.tokenization.caseFold },
                        set: { v in var u = d; u.tokenization.caseFold = v; apply(u) }
                    )) {
                        Text("preserve").tag("preserve")
                        Text("lower").tag("lower")
                        Text("upper").tag("upper")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Sources

    @ViewBuilder
    private func sourcesGroup(_ d: FilenameTokenizationFileDraft) -> some View {
        GroupBox("Sources") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Drag to reorder. Controls which path components are tokenized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(d.sources.enumerated()), id: \.element) { idx, source in
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Toggle(source, isOn: Binding(
                            get: { true },
                            set: { _ in }
                        ))
                        .labelsHidden()
                        Text(source)
                            .font(.body.monospaced())
                        Spacer()
                        HStack(spacing: AppSpacing.xs) {
                            Button {
                                guard idx > 0 else { return }
                                var updated = d; updated.sources.swapAt(idx - 1, idx); apply(updated)
                            } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(idx == 0)
                            Button {
                                guard idx < d.sources.count - 1 else { return }
                                var updated = d; updated.sources.swapAt(idx, idx + 1); apply(updated)
                            } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(idx == d.sources.count - 1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                let presentSources = Set(d.sources)
                let missingSources = allowedSources.filter { !presentSources.contains($0) }
                if !missingSources.isEmpty {
                    Divider()
                    HStack {
                        Text("Add source:").font(.caption).foregroundStyle(.secondary)
                        ForEach(missingSources, id: \.self) { source in
                            Button(source) {
                                var updated = d; updated.sources.append(source); apply(updated)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(.body.monospaced())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Channel

    @ViewBuilder
    private func channelGroup(_ d: FilenameTokenizationFileDraft) -> some View {
        GroupBox("Channel") {
            keyValueEditor(
                title: "Aliases",
                subtitle: "alias → canonical channel name",
                items: d.channel.aliases,
                onChange: { v in var u = d; u.channel.aliases = v; apply(u) }
            )
        }
    }

    @ViewBuilder
    private func keyValueEditor(
        title: String,
        subtitle: String,
        items: [String: String],
        onChange: @escaping ([String: String]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(AppFontScale.groupHeader)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Row") {
                    var updated = items
                    var key = "new_key"
                    var n = 2
                    while updated.keys.contains(key) { key = "new_key_\(n)"; n += 1 }
                    updated[key] = ""
                    onChange(updated)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(items.keys.sorted(), id: \.self) { key in
                HStack(spacing: AppSpacing.sm) {
                    Text(key)
                        .font(.body.monospaced())
                        .frame(minWidth: 100, alignment: .leading)
                    Text("→").foregroundStyle(.secondary)
                    TextField("value", text: Binding(
                        get: { items[key] ?? "" },
                        set: { v in var updated = items; updated[key] = v; onChange(updated) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var updated = items; updated.removeValue(forKey: key); onChange(updated)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove")
                }
            }
        }
    }

    // MARK: - Actions

    private func apply(_ d: FilenameTokenizationFileDraft) {
        draft = d
        store.updateFilenameTokenization(d)
    }

    private func syncFromStore() {
        if let current = store.filenameTokenizationDraft { draft = current }
    }
}
