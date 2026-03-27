import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct InboxView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var viewModel = InboxViewModel()

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        HSplitView {
            InboxOperationPanel(
                isImportSourceExpanded: $bindableViewModel.isImportSourceExpanded,
                isPendingQueueExpanded: $bindableViewModel.isPendingQueueExpanded,
                isRoutingReviewExpanded: $bindableViewModel.isRoutingReviewExpanded,
                isApplyExpanded: $bindableViewModel.isApplyExpanded,
                fileFilter: $bindableViewModel.fileFilter
            )
            .frame(minWidth: 380, idealWidth: 500, maxWidth: 680)

            InboxInspectorReservedPanel()
                .frame(minWidth: 460, idealWidth: 660, maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dropDestination(for: URL.self) { items, _ in
            appState.importFiles(from: items)
            return !items.isEmpty
        } isTargeted: { _ in }
        .onAppear {
            viewModel.restoreInteractionState(from: appState)
            viewModel.persistInteractionState(to: appState)
        }
        .onChange(of: viewModel.isImportSourceExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.isPendingQueueExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.isRoutingReviewExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.isApplyExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onDisappear {
            viewModel.persistInteractionState(to: appState)
        }
    }
}

private struct InboxInspectorReservedPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.title2.bold())
            Text("Reserved slot for upcoming Inbox inspector modules.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct InboxOperationPanel: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isImportSourceExpanded: Bool
    @Binding var isPendingQueueExpanded: Bool
    @Binding var isRoutingReviewExpanded: Bool
    @Binding var isApplyExpanded: Bool
    @Binding var fileFilter: InboxViewModel.FileFilter
    @State private var isPresentingClearImportsConfirm = false

    var body: some View {
        @Bindable var bindableInbox = appState.inbox

        let routePresentationByID = appState.pendingRoutePresentationByID()
        let libraryMatchedCount = appState.inbox.pendingImports.reduce(into: 0) { partial, pending in
            if routePresentationByID[pending.id]?.isLibraryMatched == true {
                partial += 1
            }
        }
        let reviewRequiredCount = max(0, appState.inbox.pendingImports.count - libraryMatchedCount)
        let filteredPendingImports = filteredPendingImports(using: routePresentationByID)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Inbox Operations")
                        .font(.title2.bold())
                    Spacer()
                    Text(AppVersion.current)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                operationBox("Registry", isExpanded: $isImportSourceExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(label: "Registry Path", value: appState.registrySourceFilePath ?? "Not loaded", monospaced: true)
                        HStack {
                            Button("Load Registry") {
                                presentSampleRegistryPanel()
                            }
                            Button("Reload Registry") {
                                appState.reloadSampleRegistry()
                            }
                            .disabled(!appState.canReloadSampleRegistry)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                operationBox("File", isExpanded: $isPendingQueueExpanded) {
                    GroupBox("Actions") {
                        HStack(spacing: 10) {
                            Button("Import Files") {
                                presentMeasurementImportPanel()
                            }

                            Button("Recompute Route") {
                                appState.recomputeAllPendingParsedHints()
                            }
                            .disabled(appState.inbox.pendingImports.isEmpty)

                            Button("Clear Imports", role: .destructive) {
                                isPresentingClearImportsConfirm = true
                            }
                            .disabled(appState.inbox.pendingImports.isEmpty)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Pending Queue") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                queueStatusCard(
                                    title: "Pending",
                                    count: appState.inbox.pendingImports.count,
                                    tint: .secondary,
                                    filter: .all
                                )
                                queueStatusCard(
                                    title: "Library Matched",
                                    count: libraryMatchedCount,
                                    tint: .green,
                                    filter: .libraryMatched
                                )
                                queueStatusCard(
                                    title: "Review Required",
                                    count: reviewRequiredCount,
                                    tint: .orange,
                                    filter: .reviewRequired
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let selected = appState.selectedPendingImport {
                                MetadataValueRow(label: "File Path", value: selected.sourceFilePath, monospaced: true)
                            }

                            if filteredPendingImports.isEmpty {
                                Text("No pending files for this filter.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                List(filteredPendingImports, selection: $bindableInbox.selectedPendingImportID) { pending in
                                    let presentation = routePresentationByID[pending.id]
                                    let verdict = presentation?.verdict ?? .reviewRequired
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pending.fileName)
                                            .font(.headline)
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(pending.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Route: \(presentation?.routeStatusTitle ?? verdict.displayTitle)")
                                            .font(.caption)
                                            .foregroundStyle(verdict == .libraryMatched ? .green : .orange)
                                        if appState.hasSavedRoutingDraft(for: pending) {
                                            Text("Routing draft: saved")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .frame(minHeight: 210, maxHeight: 360)
                                .listStyle(.inset)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }

                    GroupBox("Selection Workbench") {
                        if let pending = appState.selectedPendingImport {
                            InboxSelectionWorkbenchPanel(pending: pending)
                                .id(pending.id)
                        } else {
                            Text("Select one pending file to edit and save confirmation draft.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .confirmationDialog(
            "Clear Imports?",
            isPresented: $isPresentingClearImportsConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Pending Imports", role: .destructive) {
                appState.clearPendingImports()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears pending queue items and unarchived temporary imports only. Archived library drawers are unchanged.")
        }
    }

    private func presentSampleRegistryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        panel.title = "Load Sample Registry"
        panel.message = "Choose an XLSX registry file."

        if panel.runModal() == .OK, let url = panel.url {
            appState.loadSampleRegistry(from: url)
        }
    }

    private func presentMeasurementImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.title = "Import Measurement Files"
        panel.message = "Choose measurement files or folders. Folders are scanned recursively."

        if panel.runModal() == .OK {
            appState.importFiles(from: panel.urls)
        }
    }

    private func filteredPendingImports(
        using routePresentationByID: [UUID: PendingRoutePresentation]
    ) -> [SpinLabDomain.PendingImport] {
        switch fileFilter {
        case .all:
            return appState.inbox.pendingImports
        case .libraryMatched:
            return appState.inbox.pendingImports.filter { routePresentationByID[$0.id]?.isLibraryMatched == true }
        case .reviewRequired:
            return appState.inbox.pendingImports.filter { routePresentationByID[$0.id]?.isLibraryMatched != true }
        }
    }

    @ViewBuilder
    private func queueStatusCard(title: String, count: Int, tint: Color, filter: InboxViewModel.FileFilter) -> some View {
        let isSelected = fileFilter == filter

        Button {
            fileFilter = filter
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.22) : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tint : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func operationBox(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private func placeholderRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
    let mode: SpinLabDomain.RoutingScopeMode = pending.parsedHints.channelHints.isEmpty ? .fileLevel : .channelLevel
    return SpinLabDomain.PendingRoutingSnapshot(
        mode: mode,
        verdict: .reviewRequired,
        scopes: [],
        unresolvedScopes: [],
        conflicts: [],
        routePlan: SpinLabDomain.RoutePlan(planningStatus: .reviewRequired)
    )
}

private struct InboxInspectorPanel: View {
    let pending: SpinLabDomain.PendingImport
    @Environment(SpinLabAppState.self) private var appState
    private var routingSnapshot: SpinLabDomain.PendingRoutingSnapshot {
        appState.cachedPendingRoutingSnapshot(for: pending.id) ?? placeholderRoutingSnapshot(for: pending)
    }
    private var routePlan: SpinLabDomain.RoutePlan { routingSnapshot.routePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.title2.bold())

            GroupBox("File Summary") {
                VStack(alignment: .leading, spacing: 10) {
                    MetadataValueRow(label: "Workflow", value: pending.workflow.rawValue)
                    MetadataValueRow(label: "File", value: pending.fileName)
                    MetadataValueRow(label: "File Path", value: pending.sourceFilePath, monospaced: true)
                    MetadataValueRow(label: "Status", value: pending.status.rawValue)
                    MetadataValueRow(label: "Route Status", value: routingSnapshot.verdict.displayTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Routing Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    MetadataValueRow(label: "Scopes", value: "\(routingSnapshot.scopes.count)")
                    MetadataValueRow(label: "Unresolved", value: "\(routingSnapshot.unresolvedScopes.count)")
                    if !routingSnapshot.unresolvedScopes.isEmpty {
                        Text(routingSnapshot.unresolvedScopes.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !routingSnapshot.scopes.isEmpty {
                        ForEach(routingSnapshot.scopes) { scope in
                            let sample = scope.sampleKey ?? "?"
                            let drawer = scope.matchedDrawer ?? "?"
                            Text("\(scope.scope): \(sample) -> \(drawer)")
                                .font(.footnote)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            let warnings = appState.pendingDisplayWarningItems(for: pending)
            if !warnings.isEmpty {
                GroupBox("Warnings") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings, id: \.self) { warning in
                            Text(displayText(for: warning))
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func displayText(for warning: PendingDisplayWarning) -> String {
        guard let scopeSummary = warning.scopeSummary else {
            return warning.message
        }
        return "\(warning.message) [Scope: \(scopeSummary)]"
    }
}

private struct InboxSelectionWorkbenchPanel: View {
    let pending: SpinLabDomain.PendingImport
    @Environment(SpinLabAppState.self) private var appState
    @State private var draft = PendingImportConfirmationDraft(
        batchName: "",
        sampleName: "",
        measurementName: "",
        workflowTag: "",
        deviceName: "",
        temperature: "",
        selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
        newProjectName: ""
    )
    @State private var routingDraft = PendingRoutingDraft(defaultSampleKey: "", channelSampleKeyOverrides: [:])
    private var routingSnapshot: SpinLabDomain.PendingRoutingSnapshot {
        appState.cachedPendingRoutingSnapshot(for: pending.id) ?? placeholderRoutingSnapshot(for: pending)
    }
    private var routePlan: SpinLabDomain.RoutePlan { routingSnapshot.routePlan }
    private var warnings: [PendingDisplayWarning] { appState.pendingDisplayWarningItems(for: pending) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Deposit Mapping") {
                VStack(alignment: .leading, spacing: 10) {
                    if isChannelLevelMapping {
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
                        mappingRow(label: "Sample", sample: $draft.sampleName, drawer: savedDrawerForFile())
                        MetadataValueRow(label: "Channel Info", value: fileLevelChannelInfo())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("File Tags") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        EditableMetadataField(label: "Workflow", value: $draft.workflowTag)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        EditableMetadataField(label: "Device", value: $draft.deviceName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        EditableMetadataField(label: "Temperature", value: $draft.temperature)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let warningDisplayValue {
                            MetadataValueRow(label: "Warnings", value: warningDisplayValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Save Draft") {
                    draft.sampleName = normalizedSampleDisplay(draft.sampleName)
                    var nextRoutingDraft = routingDraft
                    let trimmedSample = draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedSample.isEmpty {
                        nextRoutingDraft.defaultSampleKey = trimmedSample
                    }
                    appState.saveRoutingDraft(nextRoutingDraft, for: pending.id)
                    routingDraft = appState.routingDraft(for: pending)
                    persistDraftState()
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

                Button("Apply") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)

                Text("Apply will be enabled in V2.3 to write file + tags into the matched Library drawer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    private func restoreDraftState() {
        let baseDraft = appState.pendingDisplayDraft(for: pending)
        let baseRoutingDraft = appState.routingDraft(for: pending)
        if let restored = appState.interactionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID) {
            draft = restored.draft
            draft.sampleName = normalizedSampleDisplay(draft.sampleName)
            routingDraft = restored.routingDraft ?? baseRoutingDraft
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
                routingDraft: routingDraft
            )
        )
    }

    private func displayOrDash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func editableSampleForChannel(_ channel: String) -> String {
        if let override = routingDraft.channelSampleKeyOverrides[channel], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        if let sample = scopeEvaluation(channel)?.sampleKey,
           !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sample
        }
        return draft.sampleName
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
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return trimmed }
            let left = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !left.isEmpty, !right.isEmpty else { return trimmed }
            return "\(left) - \(right)"
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2 else { return trimmed }
        let head = String(parts[0])
        let hasBatchLikeHead = head.rangeOfCharacter(from: .decimalDigits) != nil
        guard hasBatchLikeHead else { return trimmed }
        let tail = parts.dropFirst().joined(separator: " ")
        return tail.isEmpty ? trimmed : "\(head) - \(tail)"
    }

    @ViewBuilder
    private func mappingRow(label: String, sample: Binding<String>, drawer: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            EditableMetadataField(label: label, value: sample)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

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
            .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
    }

}

private struct RegistryStatusColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InboxColumnHeader(
                title: "Registry",
                subtitle: appState.registryFileName ?? "No registry loaded"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Current Registry") {
                        VStack(alignment: .leading, spacing: 10) {
                            MetadataValueRow(label: "File", value: appState.registryFileName ?? "Not loaded")
                            MetadataValueRow(label: "Path", value: appState.registrySourceFilePath ?? "Not loaded", monospaced: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Prefix -> Sheet") {
                        VStack(alignment: .leading, spacing: 8) {
                            if appState.registryPrefixEntries.isEmpty {
                                Text("No registry loaded.")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(appState.registryPrefixEntries) { entry in
                                    GroupBox {
                                        VStack(alignment: .leading, spacing: 8) {
                                            MetadataValueRow(label: "Prefix", value: entry.prefix)
                                            MetadataValueRow(label: "Sheet", value: entry.sheetName)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let pending = appState.selectedPendingImport {
                        PendingRegistryLookupDetail(pending: pending)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct InboxColumnHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PendingRegistryLookupDetail: View {
    let pending: SpinLabDomain.PendingImport
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let sampleID = appState.parsedSampleIDFromFilename(for: pending)
        let prefix = appState.parsedPrefixFromFilename(for: pending)
        let registryLookup = appState.registryLookup(for: pending)

        return GroupBox("Registry Lookup") {
            VStack(alignment: .leading, spacing: 10) {
                MetadataValueRow(label: "Sample ID (from filename)", value: sampleID ?? "Not found")
                MetadataValueRow(label: "Prefix", value: prefix ?? "Not found")
                MetadataValueRow(label: "Selected Sheet", value: registryLookup?.sheetName ?? "No mapped sheet")

                if let registryLookup, !registryLookup.metadata.isEmpty {
                    ForEach(registryLookup.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                        MetadataValueRow(label: item.key, value: item.value)
                    }
                } else {
                    Text("No metadata row found for this Sample ID on the mapped sheet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
