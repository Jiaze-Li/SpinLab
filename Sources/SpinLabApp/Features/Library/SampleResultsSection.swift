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
            Text("Results").font(AppFontScale.groupHeader)
            switch catalog {
            case .missing:
                Text("No Result Definitions yet. Create them in Result Definitions on the Library Overview.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case let .unreadable(reason):
                Text("Result Definitions file is unreadable; display and writes are disabled: \(reason)")
                    .font(.callout)
                    .foregroundStyle(.red)
            case let .ok(loaded):
                if loaded.definitions.isEmpty {
                    Text("No Result Definitions yet. Create them in Result Definitions on the Library Overview.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(loaded.definitions) { definition in
                    row(for: definition)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        }
        .task(id: sample.id) {
            // Typed drafts and pending confirmations belong to the Sample that was open when they were made.
            drafts = [:]
            errorMessage = nil
            pendingOverwrite = nil
            reload()
        }
        .onChange(of: appState.library.resultCatalogRevision) { _, _ in reload() }
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
                Text("Current value \(Self.format(change.oldValue)) will be replaced with \(Self.format(newValue)). The previous value is not kept.")
            } else {
                Text("Current value \(Self.format(change.oldValue)) will be cleared. The previous value is not kept.")
            }
        }
    }

    private func row(for definition: ResultDefinition) -> some View {
        let current = sample.results?[definition.definitionID]?.value
        let draft = Binding(
            get: { drafts[definition.definitionID] ?? "" },
            set: { drafts[definition.definitionID] = $0 }
        )
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                Text(definition.displayLabel)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.sm)
                Text(current.map { Self.format($0) } ?? "—")
                    .font(.callout.monospacedDigit())
            }
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                TextField("New value", text: draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .frame(minWidth: 80, maxWidth: 160)
                    .disabled(!canWrite)
                Button("Confirm") { requestSave(definition, current: current) }
                    .font(.callout)
                    .disabled(!canWrite || (drafts[definition.definitionID] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                if let current {
                    Button("Clear") { pendingOverwrite = PendingChange(definition: definition, newValue: nil, oldValue: current) }
                        .font(.callout)
                        .disabled(!canWrite)
                }
                Spacer(minLength: 0)
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
            errorMessage = "Library Root is not set."
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
