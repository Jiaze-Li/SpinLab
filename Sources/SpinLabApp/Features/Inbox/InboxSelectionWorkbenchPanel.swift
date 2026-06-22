import AppKit
import SwiftUI

struct InboxSelectionWorkbenchPanel: View {
    let pending: SpinLabDomain.PendingImport
    let applySelected: () -> Void
    let applyAll: () -> Void
    @Environment(SpinLabAppState.self) private var appState
    @State private var draft = PendingImportConfirmationDraft(
        batchName: "",
        sampleName: "",
        measurementName: "",
        workflowID: "",
        conditionValues: [:],
        selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
        newProjectName: ""
    )
    @State private var routingDraft = PendingRoutingDraft(fileSampleKey: "", channelSampleKeyOverrides: [:])
    @State private var isPresentingTagsMissingConfirm = false
    private var routingSnapshot: SpinLabDomain.PendingRoutingSnapshot {
        appState.pendingRoutingPreviewSnapshot(
            for: pending,
            routingDraft: routingDraft,
            sampleName: draft.sampleName
        )
    }
    private var routingPresentation: PendingRoutePresentation {
        appState.pendingRoutePresentation(
            for: pending,
            routingDraft: routingDraft,
            sampleName: draft.sampleName
        )
    }
    private var routePlan: SpinLabDomain.RoutePlan { routingSnapshot.routePlan }
    private var warnings: [PendingDisplayWarning] { routingPresentation.warningItems }
    private var visibleWarnings: [String] {
        warnings
            .map(displayText(for:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    private var warningDisplayValue: String? {
        guard !visibleWarnings.isEmpty else {
            return nil
        }
        if visibleWarnings.count == 1 {
            return visibleWarnings[0]
        }
        return visibleWarnings.joined(separator: "\n")
    }

    private func displayText(for warning: PendingDisplayWarning) -> String {
        guard let scopeSummary = warning.scopeSummary else {
            return warning.message
        }
        return "\(warning.message) [Scope: \(scopeSummary)]"
    }
    @ViewBuilder
    private var workflowPicker: some View {
        let definitions = appState.workflowDefinitions
        VStack(alignment: .leading, spacing: 4) {
            Text("Workflow")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $draft.workflowID) {
                Text("—").tag("")
                ForEach(definitions) { definition in
                    Text(definition.displayName).tag(definition.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Renders condition fields starting from index 1 (index 0 is already beside Workflow).
    @ViewBuilder
    private func remainingConditionFieldRows(fields: [WorkflowConditionField]) -> some View {
        let remaining = fields.count > 1 ? Array(fields.dropFirst()) : []
        if !remaining.isEmpty {
            let rowStarts = Array(stride(from: 0, to: remaining.count, by: 2))
            ForEach(rowStarts, id: \.self) { startIndex in
                let first = remaining[startIndex]
                let second: WorkflowConditionField? = startIndex + 1 < remaining.count ? remaining[startIndex + 1] : nil
                HStack(alignment: .top, spacing: 12) {
                    conditionField(first)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let second {
                        conditionField(second)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conditionField(_ field: WorkflowConditionField) -> some View {
        let label = appState.workbench.conditionLabel(for: field.definitionID)
        EditableMetadataField(
            label: label,
            value: Binding(
                get: { draft.conditionValues[field.definitionID] ?? "" },
                set: { draft.conditionValues[field.definitionID] = $0 }
            )
        )
    }

    private var routingDraftIsDirty: Bool { appState.isRoutingDraftDirty(routingDraft, for: pending) }
    private var hasUnsavedInfoDraft: Bool { draft != appState.pendingDisplayDraft(for: pending) }
    private var channelKeys: [String] {
        routingSnapshot.scopes
            .map(\.scope)
            .filter { $0 != "file" }
    }
    private var isChannelLevelMapping: Bool {
        routingSnapshot.mode == .channelLevel
    }
    private var shouldRenderChannelMappingRows: Bool {
        isChannelLevelMapping && !channelKeys.isEmpty
    }
    private var canApplySelected: Bool {
        routingSnapshot.verdict == .libraryMatched
    }
    private var canApplyAll: Bool {
        appState.hasAnyAllGoodPendingImports()
    }
    private var missingTagLabelsForDraft: [String] {
        appState.pendingMissingRequiredTagLabels(for: pending, draftOverride: draft)
    }
    private var fileTagStatusDisplay: (text: String, color: Color)? {
        guard routingSnapshot.verdict == .libraryMatched else {
            return nil
        }
        if missingTagLabelsForDraft.isEmpty {
            return ("all good", .green)
        }
        return ("tags missing", .red)
    }
    private var tagsMissingConfirmMessage: String {
        if missingTagLabelsForDraft.isEmpty {
            return "Required tags are missing. Confirm deposit?"
        }
        return "\(missingTagLabelsForDraft.joined(separator: ", ")) tag missing, confirm deposit?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if shouldRenderChannelMappingRows {
                        ForEach(channelKeys, id: \.self) { channel in
                            mappingRow(
                                label: "\(channel) Sample",
                                sample: Binding(
                                    get: { editableSampleForChannel(channel) },
                                    set: { setEditableSampleForChannel(channel, to: $0) }
                                ),
                                drawer: savedDrawerForChannel(channel)
                            )
                        }
                        if !routingSnapshot.unresolvedScopes.isEmpty {
                            MetadataValueRow(label: "Unresolved", value: routingSnapshot.unresolvedScopes.joined(separator: ", "))
                        }
                    } else {
                        mappingRow(
                            label: "Sample",
                            sample: Binding(
                                get: { editableSampleForFile() },
                                set: { setEditableSampleForFile(to: $0) }
                            ),
                            drawer: savedDrawerForFile()
                        )
                        MetadataValueRow(label: "Channel Info", value: fileLevelChannelInfo())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack {
                    Text("Deposit Mapping")
                    Spacer()
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    let fields = appState.workflowDefinitions
                        .first(where: { $0.id == draft.workflowID })?.conditionFields ?? []
                    HStack(alignment: .top, spacing: 12) {
                        workflowPicker
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let first = fields.first {
                            conditionField(first)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    remainingConditionFieldRows(fields: fields)
                    if let warningDisplayValue {
                        MetadataValueRow(label: "Warnings", value: warningDisplayValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack(spacing: 8) {
                    Text("File Tags")
                    if let status = fileTagStatusDisplay {
                        Text(status.text)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.color)
                    }
                }
            }

            HStack {
                Button("Save Draft") {
                    scheduleImmediateSaveDraft()
                }
                .disabled(!routingDraftIsDirty && !hasUnsavedInfoDraft)

                Button("Revert Draft") {
                    draft = appState.pendingDisplayDraft(for: pending)
                    draft.sampleName = normalizedSampleDisplay(draft.sampleName)
                    let baseline = appState.routingDraftBaseline(for: pending)
                    appState.saveRoutingDraft(baseline, for: pending.id)
                    routingDraft = baseline
                    persistDraftState()
                }

                Button("Apply") {
                    if !missingTagLabelsForDraft.isEmpty {
                        isPresentingTagsMissingConfirm = true
                    } else {
                        scheduleImmediateApplySelected()
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplySelected)

                Button("Apply All") {
                    applyAll()
                }
                .disabled(!canApplyAll)
            }
        }
        .onAppear {
            restoreDraftState()
        }
        .onChange(of: pending.id) { _, _ in
            restoreDraftState()
        }
        .onChange(of: pending.parsedHints) { _, _ in
            restoreDraftState()
        }
        .onChange(of: draft) { _, _ in
            persistDraftState()
        }
        .onChange(of: routingDraft) { _, _ in
            persistDraftState()
        }
        .confirmationDialog(
            "Tags Missing",
            isPresented: $isPresentingTagsMissingConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                scheduleImmediateApplySelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(tagsMissingConfirmMessage)
        }
    }

    private func restoreDraftState() {
        let baseDraft = appState.pendingDisplayDraft(for: pending)
        let baseRoutingDraft = appState.routingDraft(for: pending)
        if let restored = appState.interactionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID) {
            draft = restored.draft
            draft.sampleName = normalizedSampleDisplay(draft.sampleName)
            routingDraft = baseRoutingDraft
            return
        }
        draft = baseDraft
        draft.sampleName = normalizedSampleDisplay(draft.sampleName)
        routingDraft = baseRoutingDraft
    }

    private func persistDraftState() {
        let existing = appState.interactionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID)
        appState.updateInteractionEntryValue(
            for: pending.id,
            in: \.inboxWorkspaceByPendingID,
            value: InboxPendingWorkspaceState.snapshotSafe(
                draft: draft,
                editableFileContents: existing?.editableFileContents ?? "",
                hasEditableFileContents: existing?.hasEditableFileContents ?? false,
                routingDraft: nil
            )
        )
    }

    private func displayOrDash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func commitActiveEditor() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
    }

    private func scheduleImmediateSaveDraft() {
        commitActiveEditor()
        Task { @MainActor in
            // Give AppKit/IME a short window to flush editor text into SwiftUI binding.
            await Task.yield()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 60_000_000)
            performSaveDraft()
        }
    }

    private func scheduleImmediateApplySelected() {
        commitActiveEditor()
        Task { @MainActor in
            // Give AppKit/IME a short window to flush editor text into SwiftUI binding.
            await Task.yield()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 60_000_000)
            performSaveDraft()
            applySelected()
        }
    }

    private func performSaveDraft() {
        draft.sampleName = normalizedSampleDisplay(draft.sampleName)
        var nextRoutingDraft = routingDraft
        let trimmedSample = draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSample.isEmpty {
            nextRoutingDraft.fileSampleKey = trimmedSample
        } else {
            nextRoutingDraft.fileSampleKey = normalizedSampleDisplay(nextRoutingDraft.fileSampleKey)
        }
        nextRoutingDraft.channelSampleKeyOverrides = nextRoutingDraft.channelSampleKeyOverrides.mapValues {
            normalizedSampleDisplay($0)
        }

        appState.saveRoutingDraft(nextRoutingDraft, for: pending.id)
        appState.refreshPendingDrawerMatches(for: [pending.id])
        routingDraft = appState.routingDraft(for: pending)
        persistDraftState()
    }

    private func editableSampleForChannel(_ channel: String) -> String {
        if let override = routingDraft.channelSampleKeyOverrides[channel], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displaySampleText(override)
        }
        if let sample = scopeEvaluation(channel)?.sampleId,
           !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displaySampleText(sample)
        }
        return displaySampleText(draft.sampleName)
    }

    private func editableSampleForFile() -> String {
        let draftValue = routingDraft.fileSampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftValue.isEmpty {
            return displaySampleText(draftValue)
        }
        if let sample = scopeEvaluation("file")?.sampleId,
           !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displaySampleText(sample)
        }
        return displaySampleText(draft.sampleName)
    }

    private func setEditableSampleForFile(to value: String) {
        let normalized = normalizedSampleDisplay(value)
        routingDraft.fileSampleKey = normalized
        // Keep draft metadata aligned for legacy consumers still reading sampleName.
        draft.sampleName = normalized
    }

    private func setEditableSampleForChannel(_ channel: String, to value: String) {
        routingDraft.channelSampleKeyOverrides[channel] = value
    }

    private func savedDrawerForFile() -> String {
        scopeEvaluation("file")?.matchedDrawer ?? "?"
    }

    private func savedDrawerForChannel(_ channel: String) -> String {
        scopeEvaluation(channel)?.matchedDrawer ?? "?"
    }

    private func fileLevelChannelInfo() -> String {
        if !pending.parsedHints.channelHints.isEmpty {
            return pending.parsedHints.channelHints.map { hint in
                let label = hint.testInfoTags.first ?? hint.tags.first ?? "test"
                return "\(hint.channel)=\(label)"
            }.joined(separator: ", ")
        }
        return "No channel-level hints"
    }

    private func scopeEvaluation(_ scope: String) -> SpinLabDomain.RoutingScopeEvaluation? {
        routingSnapshot.scopes.first(where: { $0.scope == scope })
    }

    private func normalizedSampleDisplay(_ sample: String) -> String {
        // Keep entered sample text as-is (except trim); matching/apply now rely on canonical sampleId, not display reformatting.
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    private func displaySampleText(_ rawSample: String) -> String {
        let trimmed = rawSample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard let descriptor = SampleSemanticDescriptor.fromSampleKey(trimmed) else {
            return trimmed
        }
        guard let batch = descriptor.batch else {
            return trimmed
        }

        var components: [String] = [batch]
        let processing = descriptor.processingTokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("UNKNOWN") != .orderedSame }
            .sorted()
        components.append(contentsOf: processing)
        if let material = descriptor.material,
           material.caseInsensitiveCompare("UNKNOWN") != .orderedSame {
            components.append(material)
        }
        if let orientation = descriptor.orientation,
           orientation.caseInsensitiveCompare("UNKNOWN") != .orderedSame {
            components.append(orientation)
        }
        return components.joined(separator: " ")
    }

    @ViewBuilder
    private func mappingRow(label: String, sample: Binding<String>, drawer: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                EditableMetadataField(label: label, value: sample)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                drawerChip(drawer)
            }
            VStack(alignment: .leading, spacing: 8) {
                EditableMetadataField(label: label, value: sample)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    drawerChip(drawer)
                }
            }
        }
    }

    @ViewBuilder
    private func drawerChip(_ drawer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drawer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(drawer)
                .font(.body.weight(.semibold))
                .foregroundStyle(drawer == "?" ? .orange : .primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 92, maxWidth: 180, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

}
