import AppKit
import Observation
import SwiftUI

struct InboxView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var viewModel = InboxViewModel()

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        let applyProgress = appState.applyProgressState
        let importProgress = appState.inbox.importProgressState
        let isBusy = applyProgress.isRunning || importProgress.isRunning

        ZStack {
            HSplitView {
                InboxOperationPanel(
                    isImportSourceExpanded: $bindableViewModel.isImportSourceExpanded,
                    isPendingQueueExpanded: $bindableViewModel.isPendingQueueExpanded,
                    isRoutingReviewExpanded: $bindableViewModel.isRoutingReviewExpanded,
                    isApplyExpanded: $bindableViewModel.isApplyExpanded,
                    fileFilter: $bindableViewModel.fileFilter,
                    applySelected: { viewModel.applySelected() },
                    applyAll: { viewModel.applyAll() }
                )
                .frame(minWidth: 380, idealWidth: 500, maxWidth: 1200)

                InboxInspectorReservedPanel()
                    .frame(minWidth: 280, idealWidth: 660, maxWidth: .infinity)
            }

            if applyProgress.isRunning {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                ApplyProgressOverlay(progress: applyProgress)
                    .frame(maxWidth: 460)
            } else if importProgress.isRunning {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                ImportProgressOverlay(progress: importProgress)
                    .frame(maxWidth: 460)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!isBusy)
        .dropDestination(for: URL.self) { items, _ in
            appState.importFiles(from: items)
            return !items.isEmpty
        } isTargeted: { _ in }
        .onAppear {
            viewModel.applySelected = { appState.applySelectedPendingImport() }
            viewModel.applyAll = { appState.applyAllPendingImports() }
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

private struct InboxExplicitRulesSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var workbench = appState.workbench

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Explicit Rules")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            if let message = workbench.workflowRegistryMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox("Sample ID Patterns") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Regex patterns used for sample ID recognition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if workbench.sampleIDPatterns.isEmpty {
                        Text("No patterns defined.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(workbench.sampleIDPatterns.enumerated()), id: \.offset) { index, pattern in
                            HStack(spacing: 8) {
                                TextField("Regex pattern", text: Binding(
                                    get: { pattern },
                                    set: { workbench.updateSampleIDPattern(at: index, value: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                                Button(role: .destructive) {
                                    workbench.removeSampleIDPattern(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button {
                        workbench.addSampleIDPattern()
                    } label: {
                        Label("Add Pattern", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 8) {
                        Button("Discard") {
                            workbench.discardSampleIDPatternEdits()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!workbench.hasUnsavedSampleIDPatterns)

                        Button("Confirm Save") {
                            workbench.confirmSampleIDPatternsSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!workbench.hasUnsavedSampleIDPatterns)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("Substrate Rules") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Origin recognition and substrate tag mapping.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Token Separators")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "_-",
                                text: Binding(
                                    get: { workbench.substrateTokenSeparators },
                                    set: { workbench.updateSubstrateTokenSeparators($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Origin Standalone Tokens (comma-separated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "O, o",
                                text: Binding(
                                    get: { workbench.substrateOriginStandaloneTokens.joined(separator: ", ") },
                                    set: { workbench.updateSubstrateOriginStandaloneTokensCSV($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Origin Contains Tokens (comma-separated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "ORIGIN, ORIGINAL",
                                text: Binding(
                                    get: { workbench.substrateOriginContainsTokens.joined(separator: ", ") },
                                    set: { workbench.updateSubstrateOriginContainsTokensCSV($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }

                        Divider()

                        Text("Substrate Tag Rules")
                            .font(.subheadline.weight(.semibold))

                        if workbench.substrateTagRules.isEmpty {
                            Text("No substrate tag rules.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(workbench.substrateTagRules) { rule in
                                HStack(alignment: .top, spacing: 8) {
                                    Picker(
                                        "Scope",
                                        selection: Binding(
                                            get: { rule.scope },
                                            set: { workbench.updateSubstrateTagRuleScope(rule.id, scope: $0) }
                                        )
                                    ) {
                                        Text("tokens").tag(FilenameRuleSet.MatchScope.tokens)
                                        Text("joined").tag(FilenameRuleSet.MatchScope.joined)
                                    }
                                    .labelsHidden()
                                    .frame(width: 92)

                                    Picker(
                                        "Type",
                                        selection: Binding(
                                            get: { rule.type },
                                            set: { workbench.updateSubstrateTagRuleType(rule.id, type: $0) }
                                        )
                                    ) {
                                        ForEach(substrateMatchTypeOptions(for: rule.type), id: \.self) { option in
                                            Text(substrateMatchTypeLabel(option)).tag(option)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)

                                    TextField(
                                        "match values",
                                        text: Binding(
                                            get: { workbench.substrateTagRuleValuesCSV(rule.id) },
                                            set: { workbench.updateSubstrateTagRuleValuesCSV(rule.id, csv: $0) }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))

                                    TextField(
                                        "tag value",
                                        text: Binding(
                                            get: { rule.value },
                                            set: { workbench.updateSubstrateTagRuleValue(rule.id, value: $0) }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 120)

                                    Button(role: .destructive) {
                                        workbench.removeSubstrateTagRule(rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Button {
                            workbench.addSubstrateTagRule()
                        } label: {
                            Label("Add Substrate Rule", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)

                        HStack(spacing: 8) {
                            Button("Discard") {
                                workbench.discardSubstrateRuleEdits()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!workbench.hasUnsavedSubstrateRules)

                            Button("Confirm Save") {
                                workbench.confirmSubstrateRulesSave()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!workbench.hasUnsavedSubstrateRules)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .frame(minHeight: 280, maxHeight: 420)
            }
        }
        .padding(18)
        .frame(minWidth: 900, minHeight: 700)
    }

    private func substrateMatchTypeOptions(for current: FilenameRuleSet.MatchType) -> [FilenameRuleSet.MatchType] {
        let preferred: [FilenameRuleSet.MatchType] = [.equals, .contains, .regex, .equalsAny, .containsAny, .equalsOrContainsAny]
        if preferred.contains(current) { return preferred }
        return preferred + [current]
    }

    private func substrateMatchTypeLabel(_ type: FilenameRuleSet.MatchType) -> String {
        switch type {
        case .equals: return "equals"
        case .contains: return "contains"
        case .regex: return "regex"
        case .equalsAny: return "equalsAny"
        case .containsAny: return "containsAny"
        case .equalsOrContainsAny: return "equalsOrContainsAny"
        }
    }
}

private struct ApplyProgressOverlay: View {
    let progress: ApplyProgressState

    private var fractionCompleted: Double {
        guard progress.totalCount > 0 else {
            return 0
        }
        return Double(progress.processedCount) / Double(progress.totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Applying Pending Imports")
                .font(.headline)
            Text("\(progress.processedCount)/\(progress.totalCount)")
                .font(.title3.monospacedDigit().weight(.semibold))
            ProgressView(value: fractionCompleted, total: 1.0)
                .progressViewStyle(.linear)
            if !progress.currentFileName.isEmpty {
                Text("Current: \(progress.currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Applied \(progress.appliedCount) · Skipped \(progress.skippedCount) · Failed \(progress.failedCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 10, y: 4)
    }
}

private struct ImportProgressOverlay: View {
    let progress: ImportProgressState

    private var fractionCompleted: Double {
        guard progress.totalCount > 0 else {
            return 0
        }
        return Double(progress.processedCount) / Double(progress.totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Importing Files")
                .font(.headline)
            Text("\(progress.processedCount)/\(progress.totalCount)")
                .font(.title3.monospacedDigit().weight(.semibold))
            ProgressView(value: fractionCompleted, total: 1.0)
                .progressViewStyle(.linear)
            if !progress.currentFileName.isEmpty {
                Text("Current: \(progress.currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if progress.failedCount > 0 {
                Text("Failed \(progress.failedCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 10, y: 4)
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
    let applySelected: () -> Void
    let applyAll: () -> Void
    @State private var isPresentingClearImportsConfirm = false

    var body: some View {
        @Bindable var bindableInbox = appState.inbox
        let routePresentationByID: [UUID: PendingRoutePresentation] = {
            _ = appState.inbox.routingSnapshotRevision
            return appState.pendingRoutePresentationByID()
        }()
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

                            Button("Clear Selected", role: .destructive) {
                                appState.clearSelectedPendingImport()
                            }
                            .disabled(appState.selectedPendingImport == nil)
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
                            InboxSelectionWorkbenchPanel(
                                pending: pending,
                                applySelected: applySelected,
                                applyAll: applyAll
                            )
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

private struct InboxInspectorPanel: View {
    let pending: SpinLabDomain.PendingImport
    @Environment(SpinLabAppState.self) private var appState
    private var routingSnapshot: SpinLabDomain.PendingRoutingSnapshot {
        appState.pendingRoutingSnapshot(for: pending)
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
                            let sample = scope.sampleId ?? "?"
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
    @State private var routingDraft = PendingRoutingDraft(defaultSampleKey: "", channelSampleKeyOverrides: [:])
    @State private var localRoutingRefreshTick: Int = 0
    @State private var isPresentingExplicitRules = false
    @State private var isPresentingTagsMissingConfirm = false
    private var routingSnapshot: SpinLabDomain.PendingRoutingSnapshot {
        _ = localRoutingRefreshTick
        return appState.pendingRoutingSnapshot(for: pending)
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
                    Button("Explicit Rules") {
                        isPresentingExplicitRules = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                        applySelected()
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
        .sheet(isPresented: $isPresentingExplicitRules) {
            InboxExplicitRulesSheet()
                .environment(appState)
        }
        .confirmationDialog(
            "Tags Missing",
            isPresented: $isPresentingTagsMissingConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                applySelected()
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

    private func performSaveDraft() {
        draft.sampleName = normalizedSampleDisplay(draft.sampleName)
        var nextRoutingDraft = routingDraft
        let trimmedSample = draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSample.isEmpty {
            nextRoutingDraft.defaultSampleKey = trimmedSample
        } else {
            nextRoutingDraft.defaultSampleKey = normalizedSampleDisplay(nextRoutingDraft.defaultSampleKey)
        }
        nextRoutingDraft.channelSampleKeyOverrides = nextRoutingDraft.channelSampleKeyOverrides.mapValues {
            normalizedSampleDisplay($0)
        }

        appState.saveRoutingDraft(nextRoutingDraft, for: pending.id)
        appState.refreshPendingDrawerMatches(for: [pending.id])
        routingDraft = appState.routingDraft(for: pending)
        localRoutingRefreshTick &+= 1
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
        let draftValue = routingDraft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
        routingDraft.defaultSampleKey = normalized
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
