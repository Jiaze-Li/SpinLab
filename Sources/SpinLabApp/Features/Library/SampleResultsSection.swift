import SwiftUI

/// Detail-pane section: one row per Library Result Definition. Empty slots are shown for every Sample;
/// only a value the user explicitly confirms is written (to this Sample's `sample.json`).
@MainActor
struct SampleResultsSection: View {
    @Environment(SpinLabAppState.self) private var appState
    let sample: LibrarySample
    @State private var catalog: ResultCatalogLoad = .missing
    @State private var drafts: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var pendingOverwrite: PendingChange?
    @State private var isShowingManager = false

    private struct PendingChange: Identifiable {
        let id = UUID()
        var definition: ResultDefinition
        var newValue: Double?
        var oldValue: Double
    }

    private var canWrite: Bool {
        appState.library.canMutateLibraryDetailSelection && !LibraryWriteLease.shared.isReadOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Results").font(AppFontScale.groupHeader)
                Button("Manage Definitions…") { isShowingManager = true }
                    .font(.callout)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("Library.ResultManagerButton")
            }
            switch catalog {
            case .missing:
                Text("还没有 Result Definition。点 Manage Definitions 新建。")
                    .font(.callout)
            case let .unreadable(reason):
                Text("Result Definition 文件无法读取，已停止显示和写入：\(reason)")
                    .font(.callout)
                    .foregroundStyle(.red)
            case let .ok(loaded):
                if loaded.definitions.isEmpty {
                    Text("还没有 Result Definition。点 Manage Definitions 新建。")
                        .font(.callout)
                }
                ForEach(loaded.definitions) { definition in
                    row(for: definition)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        }
        .task(id: sample.id) { reload() }
        .sheet(isPresented: $isShowingManager, onDismiss: { reload() }) {
            ResultDefinitionManagerSheet(isPresented: $isShowingManager)
        }
        .confirmationDialog(
            pendingOverwrite.map { $0.newValue == nil ? "Clear \($0.definition.displayLabel)?" : "Replace \($0.definition.displayLabel)?" } ?? "",
            isPresented: Binding(get: { pendingOverwrite != nil }, set: { if !$0 { pendingOverwrite = nil } }),
            titleVisibility: .visible,
            presenting: pendingOverwrite
        ) { change in
            Button(change.newValue == nil ? "Clear Value" : "Replace Value", role: .destructive) {
                commit(change.definition, newValue: change.newValue, expected: change.oldValue)
                pendingOverwrite = nil
            }
            Button("Cancel", role: .cancel) { pendingOverwrite = nil }
        } message: { change in
            if let newValue = change.newValue {
                Text("当前值 \(Self.format(change.oldValue)) 将被 \(Self.format(newValue)) 覆盖，旧值不保留。")
            } else {
                Text("当前值 \(Self.format(change.oldValue)) 将被清空，旧值不保留。")
            }
        }
    }

    private func row(for definition: ResultDefinition) -> some View {
        let current = sample.results?[definition.definitionID]?.value
        let draft = Binding(
            get: { drafts[definition.definitionID] ?? "" },
            set: { drafts[definition.definitionID] = $0 }
        )
        return HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(definition.displayLabel).font(.callout.weight(.semibold))
                .frame(minWidth: 180, alignment: .leading)
            Text(current.map { Self.format($0) } ?? "—").font(.callout)
                .frame(minWidth: 80, alignment: .leading)
            TextField("新数值", text: draft)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .frame(minWidth: 100, maxWidth: 160)
                .disabled(!canWrite)
            Button("Confirm") { requestSave(definition, current: current) }
                .font(.callout)
                .disabled(!canWrite || (drafts[definition.definitionID] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            if let current {
                Button("Clear") { pendingOverwrite = PendingChange(definition: definition, newValue: nil, oldValue: current) }
                    .font(.callout)
                    .disabled(!canWrite)
            }
        }
    }

    private func requestSave(_ definition: ResultDefinition, current: Double?) {
        errorMessage = nil
        let text = (drafts[definition.definitionID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text), value.isFinite else {
            errorMessage = LibraryResultError.invalidValue.localizedDescription
            return
        }
        if let current {
            pendingOverwrite = PendingChange(definition: definition, newValue: value, oldValue: current)
        } else {
            commit(definition, newValue: value, expected: nil)
        }
    }

    private func commit(_ definition: ResultDefinition, newValue: Double?, expected: Double?) {
        errorMessage = nil
        guard let context = appState.libraryResultContext() else {
            errorMessage = "Library Root 未设置。"
            return
        }
        do {
            try context.service.setValue(
                sample: sample,
                definitionID: definition.definitionID,
                newValue: newValue,
                expectedCurrent: expected,
                rootURL: context.rootURL
            )
            drafts[definition.definitionID] = nil
            appState.refreshLibraryAfterResultChange()
        } catch {
            // The previous value stays on disk; the typed draft stays so it can be retried.
            errorMessage = error.localizedDescription
            appState.refreshLibraryAfterResultChange()
        }
    }

    private func reload() {
        guard let context = appState.libraryResultContext() else { catalog = .missing; return }
        catalog = context.service.loadCatalog(rootURL: context.rootURL)
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    }
}
