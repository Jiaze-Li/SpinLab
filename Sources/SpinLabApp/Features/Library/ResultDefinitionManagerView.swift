import SwiftUI

/// Library Result Manager, shown inside the Library Overview: create, view and edit Result Definitions
/// (name, unit, optional qualifier).
@MainActor
struct ResultDefinitionManagerView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var catalog: ResultCatalogLoad = .missing
    @State private var usage: [String: Int] = [:]
    @State private var usageError: String?
    @State private var newName = ""
    @State private var newUnit = ""
    @State private var newQualifier = ""
    @State private var editing: ResultDefinition?
    @State private var errorMessage: String?
    @State private var similarPrompt: String?
    @State private var meaningChangePrompt: Int?

    private var canWrite: Bool { !LibraryWriteLease.shared.isReadOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("Each Definition is a library-wide result slot shown on every Sample; only confirmed values are saved. Qualifiers are user-defined labels and are not interpreted or verified by SpinLab.")
                .font(.callout)
                .foregroundStyle(.secondary)
            createForm
            if !canWrite {
                Text("This Library is open in another SpinLab instance and is currently read-only.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
            if let usageError {
                Text(usageError).font(.callout).foregroundStyle(.orange)
            }
            list
        }
        .task { reload() }
        .confirmationDialog(
            "Similar Definition Exists",
            isPresented: Binding(get: { similarPrompt != nil }, set: { if !$0 { similarPrompt = nil } }),
            titleVisibility: .visible
        ) {
            Button("Create Anyway") { create(allowSimilar: true) }
            Button("Cancel", role: .cancel) { similarPrompt = nil }
        } message: {
            Text("Existing: \(similarPrompt ?? ""). Definitions that differ only by case or whitespace will be treated as two separate slots.")
        }
        .confirmationDialog(
            "Change Meaning of Recorded Values?",
            isPresented: Binding(get: { meaningChangePrompt != nil }, set: { if !$0 { meaningChangePrompt = nil } }),
            titleVisibility: .visible
        ) {
            Button("Confirm Change", role: .destructive) { saveEdit(confirmed: true) }
            Button("Cancel", role: .cancel) { meaningChangePrompt = nil }
        } message: {
            Text("\(meaningChangePrompt ?? 0) sample(s) already have a value for this Definition. Changing the unit or qualifier will not convert existing numbers; they will be interpreted under the new definition.")
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                TextField("Name, e.g. Rxx", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                TextField("Unit, e.g. Ω", text: $newUnit)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .frame(minWidth: 72, maxWidth: 110)
            }
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                TextField("Qualifier (optional), e.g. 300 K", text: $newQualifier)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Button("Add") { create(allowSimilar: false) }
                    .font(.callout)
                    .disabled(!canWrite || newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        switch catalog {
        case .missing:
            Text("No Definitions yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .unreadable(reason):
            Text("Definitions file is unreadable; writes are disabled: \(reason)")
                .font(.callout)
                .foregroundStyle(.red)
        case let .ok(loaded):
            if loaded.definitions.isEmpty {
                Text("No Definitions yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(loaded.definitions) { definition in
                        if editing?.definitionID == definition.definitionID {
                            editRow
                        } else {
                            let usedCount = usage[definition.definitionID] ?? 0
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                                    Text(definition.displayLabel)
                                        .font(.callout.weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: AppSpacing.sm)
                                    Text("\(usedCount) sample\(usedCount == 1 ? "" : "s")")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: AppSpacing.sm) {
                                    Button("Edit") { editing = definition }
                                        .font(.callout)
                                        .disabled(!canWrite)
                                    Button("Delete", role: .destructive) { delete(definition) }
                                        .font(.callout)
                                        .disabled(!canWrite || usedCount > 0)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var editRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                TextField("Name", text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                TextField("Unit", text: Binding(get: { editing?.unit ?? "" }, set: { editing?.unit = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .frame(minWidth: 72, maxWidth: 110)
            }
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                TextField("Qualifier", text: Binding(get: { editing?.qualifier ?? "" }, set: { editing?.qualifier = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Button("Save") { saveEdit(confirmed: false) }
                    .font(.callout)
                Button("Cancel") { editing = nil }
                    .font(.callout)
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        guard let context = appState.libraryResultContext() else { catalog = .missing; return }
        catalog = context.service.loadCatalog(rootURL: context.rootURL)
        do {
            usage = try context.service.usageCounts(rootURL: context.rootURL)
            usageError = nil
        } catch {
            usage = [:]
            usageError = error.localizedDescription
        }
    }

    private func create(allowSimilar: Bool) {
        errorMessage = nil
        similarPrompt = nil
        guard let context = appState.libraryResultContext() else { errorMessage = "Library Root is not set."; return }
        do {
            try context.service.createDefinition(
                name: newName, unit: newUnit, qualifier: newQualifier,
                allowSimilar: allowSimilar, rootURL: context.rootURL
            )
            newName = ""; newUnit = ""; newQualifier = ""
            reload()
            appState.library.resultCatalogRevision += 1
        } catch LibraryResultError.similarDefinitionExists(let label) {
            similarPrompt = label
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEdit(confirmed: Bool) {
        errorMessage = nil
        meaningChangePrompt = nil
        guard let draft = editing, let context = appState.libraryResultContext() else { return }
        do {
            try context.service.updateDefinition(
                definitionID: draft.definitionID, name: draft.name, unit: draft.unit, qualifier: draft.qualifier,
                confirmedMeaningChange: confirmed, rootURL: context.rootURL
            )
            editing = nil
            reload()
            appState.library.resultCatalogRevision += 1
        } catch LibraryResultError.changeNeedsConfirmation(let count) {
            meaningChangePrompt = count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ definition: ResultDefinition) {
        errorMessage = nil
        guard let context = appState.libraryResultContext() else { return }
        do {
            try context.service.deleteDefinition(definitionID: definition.definitionID, rootURL: context.rootURL)
            reload()
            appState.library.resultCatalogRevision += 1
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }
}
