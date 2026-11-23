import SwiftUI

/// Library Result Manager: create, view and edit Result Definitions (name, unit, optional qualifier).
@MainActor
struct ResultDefinitionManagerSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isPresented: Bool
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
            HStack {
                Text("Result Definitions").font(AppFontScale.sectionHeader)
                Spacer()
                Button("Done") { isPresented = false }.font(.callout)
            }
            Text("每个 Definition 是全库共用的一个结果格子；所有 Sample 都会显示它的空位，只有确认填写的数值才会保存。限定文字由你自己定义，软件不会解读或核验。")
                .font(.callout)
            createForm
            if !canWrite {
                Text("这个 Library 已在另一个 SpinLab 中打开，当前为只读。").font(.callout).foregroundStyle(.orange)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
            if let usageError {
                Text(usageError).font(.callout).foregroundStyle(.orange)
            }
            list
        }
        .padding(AppSpacing.xl)
        .frame(minWidth: 640, minHeight: 420)
        .task { reload() }
        .confirmationDialog(
            "已存在相似的 Definition",
            isPresented: Binding(get: { similarPrompt != nil }, set: { if !$0 { similarPrompt = nil } }),
            titleVisibility: .visible
        ) {
            Button("仍然新建") { create(allowSimilar: true) }
            Button("Cancel", role: .cancel) { similarPrompt = nil }
        } message: {
            Text("已有：\(similarPrompt ?? "")。名称和限定文字只差大小写或空格时，后续比较会被分成两个格子。")
        }
        .confirmationDialog(
            "改变已填写数值的含义？",
            isPresented: Binding(get: { meaningChangePrompt != nil }, set: { if !$0 { meaningChangePrompt = nil } }),
            titleVisibility: .visible
        ) {
            Button("确认修改", role: .destructive) { saveEdit(confirmed: true) }
            Button("Cancel", role: .cancel) { meaningChangePrompt = nil }
        } message: {
            Text("\(meaningChangePrompt ?? 0) 个 Sample 已填写该 Definition。修改单位或限定文字后这些数值不会被换算，含义以新定义为准。")
        }
    }

    private var createForm: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            TextField("名称，如 Rxx", text: $newName).textFieldStyle(.roundedBorder).font(.callout)
            TextField("单位，如 Ω", text: $newUnit).textFieldStyle(.roundedBorder).font(.callout).frame(maxWidth: 100)
            TextField("限定（可选），如 300 K", text: $newQualifier).textFieldStyle(.roundedBorder).font(.callout)
            Button("Add") { create(allowSimilar: false) }
                .font(.callout)
                .disabled(!canWrite || newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var list: some View {
        switch catalog {
        case .missing:
            Text("还没有 Definition。").font(.callout)
        case let .unreadable(reason):
            Text("Definition 文件无法读取，已停止写入：\(reason)").font(.callout).foregroundStyle(.red)
        case let .ok(loaded):
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(loaded.definitions) { definition in
                        if editing?.definitionID == definition.definitionID {
                            editRow
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                                Text(definition.displayLabel).font(.callout.weight(.semibold))
                                Text("已填写 \(usage[definition.definitionID] ?? 0) 个 Sample").font(.callout)
                                Spacer()
                                Button("Edit") { editing = definition }.font(.callout).disabled(!canWrite)
                                Button("Delete", role: .destructive) { delete(definition) }
                                    .font(.callout)
                                    .disabled(!canWrite || (usage[definition.definitionID] ?? 0) > 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private var editRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            TextField("名称", text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 }))
                .textFieldStyle(.roundedBorder).font(.callout)
            TextField("单位", text: Binding(get: { editing?.unit ?? "" }, set: { editing?.unit = $0 }))
                .textFieldStyle(.roundedBorder).font(.callout).frame(maxWidth: 100)
            TextField("限定", text: Binding(get: { editing?.qualifier ?? "" }, set: { editing?.qualifier = $0 }))
                .textFieldStyle(.roundedBorder).font(.callout)
            Button("Save") { saveEdit(confirmed: false) }.font(.callout)
            Button("Cancel") { editing = nil }.font(.callout)
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
        guard let context = appState.libraryResultContext() else { errorMessage = "Library Root 未设置。"; return }
        do {
            try context.service.createDefinition(
                name: newName, unit: newUnit, qualifier: newQualifier,
                allowSimilar: allowSimilar, rootURL: context.rootURL
            )
            newName = ""; newUnit = ""; newQualifier = ""
            reload()
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
        } catch {
            errorMessage = error.localizedDescription
            reload()
        }
    }
}
