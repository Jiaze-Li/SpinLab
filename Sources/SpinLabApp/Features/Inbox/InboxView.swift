import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InboxView: View {
    @EnvironmentObject private var appState: SpinLabAppState
    @State private var isPresentingProjectSheet = false

    var body: some View {
        HSplitView {
            pendingListColumn
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)

            confirmationColumn
                .frame(minWidth: 420, idealWidth: 560, maxWidth: .infinity)

            registryColumn
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Load Sample Registry (.xlsx)") {
                    presentSampleRegistryPanel()
                }

                Button("Import Measurement Files") {
                    presentMeasurementImportPanel()
                }

                Button("Create Project") {
                    isPresentingProjectSheet = true
                }

                Button("Clear Imports") {
                    appState.clearPendingImports()
                }
                .disabled(appState.pendingImports.isEmpty)

                Button("Recompute Route") {
                    appState.recomputeAllPendingParsedHints()
                }
                .disabled(appState.pendingImports.isEmpty)
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            appState.importFiles(from: items)
            return !items.isEmpty
        } isTargeted: { _ in }
        .sheet(isPresented: $isPresentingProjectSheet) {
            CreateProjectSheet()
                .environmentObject(appState)
                .frame(minWidth: 420, minHeight: 220)
        }
    }

    private var pendingListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            InboxColumnHeader(
                title: "Pending Imports",
                subtitle: appState.pendingImports.isEmpty ? "No pending files" : "\(appState.pendingImports.count) pending file\(appState.pendingImports.count == 1 ? "" : "s")"
            )
            List(appState.pendingImports, selection: $appState.selectedPendingImportID) { pending in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.fileName)
                        .font(.headline)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pending.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Route: \(appState.pendingRouteStatus(for: pending).rawValue)")
                        .font(.caption)
                        .foregroundStyle(appState.pendingRouteStatus(for: pending) == .applyReady ? .green : .orange)
                    if appState.hasSavedRoutingDraft(for: pending) {
                        Text("Routing draft: saved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var confirmationColumn: some View {
        ScrollView([.vertical, .horizontal]) {
            Group {
                if let pending = appState.selectedPendingImport {
                    PendingImportConfirmationColumn(pending: pending)
                        .id(pending.id)
                } else {
                    ContentUnavailableView(
                        "No Pending Import",
                        systemImage: "tray",
                        description: Text("Import an AMR/PHE file or folder to create pending items.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var registryColumn: some View {
        RegistryStatusColumn()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}

private struct PendingImportConfirmationColumn: View {
    let pending: SpinLabDomain.PendingImport
    @EnvironmentObject private var appState: SpinLabAppState
    @State private var draft = PendingImportConfirmationDraft(
        batchName: "",
        sampleName: "",
        measurementName: "",
        deviceName: "",
        temperature: "",
        selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
        newProjectName: ""
    )
    @State private var editableFileContents = ""
    @State private var hasEditableFileContents = false
    @State private var isPresentingFileReview = false
    @State private var autoValues = PendingImportConfirmationDraft(
        batchName: "",
        sampleName: "",
        measurementName: "",
        deviceName: "",
        temperature: "",
        selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
        newProjectName: ""
    )
    @State private var displayWarnings: [String] = []
    @State private var infoTags: [String] = []
    @State private var routingDraft = PendingRoutingDraft(defaultSampleKey: "", channelSampleKeyOverrides: [:])
    private var routePlan: SpinLabDomain.RoutePlan { appState.pendingRoutePlan(for: pending) }
    private var routingDraftIsDirty: Bool { appState.isRoutingDraftDirty(routingDraft, for: pending) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pending Import Workspace")
                .font(.title2.bold())

                GroupBox("File Metadata") {
                    VStack(alignment: .leading, spacing: 10) {
                        MetadataValueRow(label: "Workflow", value: pending.workflow.rawValue)
                        MetadataValueRow(label: "File", value: pending.fileName)
                        MetadataValueRow(label: "Stored Path", value: pending.sourceFilePath, monospaced: true)
                        MetadataValueRow(label: "Original Path", value: pending.originalFilePath ?? "Unknown", monospaced: true)
                        MetadataValueRow(label: "Status", value: pending.status.rawValue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Confirm Values") {
                    VStack(alignment: .leading, spacing: 10) {
                        EditableMetadataField(
                            label: "Batch",
                            value: $draft.batchName,
                            isAuto: isAutoValue(draft.batchName, parsed: autoValues.batchName)
                        )
                        EditableMetadataField(
                            label: "Sample",
                            value: $draft.sampleName,
                            isAuto: isAutoValue(draft.sampleName, parsed: autoValues.sampleName)
                        )
                        EditableMetadataField(
                            label: "Measurement",
                            value: $draft.measurementName,
                            isAuto: isAutoValue(draft.measurementName, parsed: autoValues.measurementName)
                        )
                        EditableMetadataField(
                            label: "Device",
                            value: $draft.deviceName,
                            isAuto: isAutoValue(draft.deviceName, parsed: autoValues.deviceName)
                        )
                        EditableMetadataField(
                            label: "Temperature",
                            value: $draft.temperature,
                            isAuto: isAutoValue(draft.temperature, parsed: autoValues.temperature)
                        )

                        if !infoTags.isEmpty {
                            MetadataValueRow(label: "Info Tags", value: infoTags.joined(separator: " | "))
                        }

                        if !displayWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Parser Warnings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ForEach(displayWarnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Channel Routing Preview") {
                    VStack(alignment: .leading, spacing: 10) {
                        GroupBox("Routing Draft (Save To Recompute)") {
                            VStack(alignment: .leading, spacing: 8) {
                                EditableMetadataField(
                                    label: "Default Sample",
                                    value: Binding(
                                        get: { routingDraft.defaultSampleKey },
                                        set: { routingDraft.defaultSampleKey = $0 }
                                    )
                                )

                                if pending.parsedHints.channelHints.isEmpty {
                                    Text("No channel keys detected in filename.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(pending.parsedHints.channelHints) { hint in
                                        EditableMetadataField(
                                            label: "\(hint.channel) Sample",
                                            value: Binding(
                                                get: { routingDraft.channelSampleKeyOverrides[hint.channel] ?? "" },
                                                set: { routingDraft.channelSampleKeyOverrides[hint.channel] = $0 }
                                            )
                                        )
                                    }
                                }

                                HStack {
                                    Button("Save Routing Draft") {
                                        appState.saveRoutingDraft(routingDraft, for: pending.id)
                                        routingDraft = appState.routingDraft(for: pending)
                                    }
                                    .disabled(!routingDraftIsDirty)

                                    Button("Revert To Parsed Baseline") {
                                        let baseline = appState.routingDraftBaseline(for: pending)
                                        appState.saveRoutingDraft(baseline, for: pending.id)
                                        routingDraft = baseline
                                    }

                                    Text("Route preview updates only after save.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(routingDraftIsDirty ? "Draft has unsaved changes" : "Draft saved")
                                    .font(.caption)
                                    .foregroundStyle(routingDraftIsDirty ? .orange : .green)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 8) {
                            Text("Route Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(routePlan.status.rawValue)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(routePlan.status == .applyReady ? .green : .orange)
                        }

                        if routePlan.channelResolutions.isEmpty {
                            Text("No channel-level routing signals detected.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Channel Resolution")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(routePlan.channelResolutions.enumerated()), id: \.offset) { _, resolution in
                                    Text(channelResolutionSummary(resolution))
                                        .font(.footnote)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if !routePlan.targets.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sample Targets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(routePlan.targets) { target in
                                    Text("sample \(target.sampleKey): \(target.channels.joined(separator: ", "))")
                                        .font(.footnote)
                                }
                            }
                        }

                        if !routePlan.unresolvedChannels.isEmpty {
                            Text("Unresolved: \(routePlan.unresolvedChannels.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !routePlan.conflicts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Route Conflicts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(routePlan.conflicts, id: \.self) { conflict in
                                    Text(conflict)
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Project Selection") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Existing Project", selection: $draft.selectedExistingProjectName) {
                            Text(PendingImportConfirmationDraft.noProjectOption).tag(PendingImportConfirmationDraft.noProjectOption)
                            ForEach(appState.knownProjectNames, id: \.self) { projectName in
                                Text(projectName).tag(projectName)
                            }
                        }
                        HStack(alignment: .top, spacing: 8) {
                            EditableMetadataField(label: "New Project", value: $draft.newProjectName)

                            Button("Create Project") {
                                if let createdName = appState.createProject(named: draft.newProjectName) {
                                    draft.selectedExistingProjectName = createdName
                                    draft.newProjectName = ""
                                }
                            }
                            .disabled(draft.newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("Project is selected during confirmation and is never treated as filename truth.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Imported File Review") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Measurement files are copied into SpinLab managed storage. Review or edit the imported text in a separate window before confirmation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Review Imported File") {
                                isPresentingFileReview = true
                            }

                            Text(hasEditableFileContents ? "Editable text preview available" : "This file is not currently readable as editable text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            HStack {
                Button("Open In Workbench") {
                    appState.openPendingImportInWorkbench()
                }

                Button("Confirm And Archive") {
                    appState.confirmSelectedPendingImport(
                        with: draft,
                        editedFileContents: hasEditableFileContents ? editableFileContents : nil
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .onAppear {
            refreshDisplay(keepCurrentDraft: false)
            restoreWorkspaceState()
        }
        .onChange(of: pending.id) { _, _ in
            refreshDisplay(keepCurrentDraft: false)
            restoreWorkspaceState()
        }
        .onChange(of: appState.pendingImports) { _, _ in
            refreshDisplay()
        }
        .onChange(of: appState.registrySourceFilePath) { _, _ in
            refreshDisplay()
        }
        .onChange(of: draft) { _, _ in
            persistWorkspaceState()
        }
        .onChange(of: routingDraft) { _, _ in
            persistWorkspaceState()
        }
        .onChange(of: editableFileContents) { _, _ in
            persistWorkspaceState()
        }
        .onChange(of: hasEditableFileContents) { _, _ in
            persistWorkspaceState()
        }
        .sheet(isPresented: $isPresentingFileReview) {
            ImportedFileReviewSheet(
                fileName: pending.fileName,
                editableFileContents: $editableFileContents,
                hasEditableFileContents: hasEditableFileContents
            )
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private func isAutoValue(_ value: String, parsed: String?) -> Bool {
        guard let parsed else {
            return false
        }
        let trimmedParsed = parsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedParsed.isEmpty else {
            return false
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedParsed
    }

    private func refreshDisplay(keepCurrentDraft: Bool = true) {
        if !keepCurrentDraft {
            draft = appState.pendingDisplayDraft(for: pending)
        }
        routingDraft = appState.routingDraft(for: pending)
        autoValues = appState.pendingDisplayAutoValues(for: pending)
        displayWarnings = appState.pendingDisplayWarnings(for: pending)
        infoTags = appState.pendingDisplayInfoTags(for: pending)
    }

    private func restoreWorkspaceState() {
        if let restored = appState.interactionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID) {
            draft = restored.draft
            editableFileContents = restored.editableFileContents
            hasEditableFileContents = restored.hasEditableFileContents
            if let restoredRoutingDraft = restored.routingDraft {
                routingDraft = restoredRoutingDraft
                appState.saveRoutingDraft(restoredRoutingDraft, for: pending.id)
            }
            return
        }

        if let contents = appState.pendingImportEditableContents(for: pending) {
            editableFileContents = contents
            hasEditableFileContents = true
        } else {
            editableFileContents = ""
            hasEditableFileContents = false
        }
        persistWorkspaceState()
    }

    private func persistWorkspaceState() {
        appState.updateInteractionEntryValue(
            for: pending.id,
            in: \.inboxWorkspaceByPendingID,
            value: InboxPendingWorkspaceState.snapshotSafe(
                draft: draft,
                editableFileContents: editableFileContents,
                hasEditableFileContents: hasEditableFileContents,
                routingDraft: routingDraft
            )
        )
    }

    private func channelResolutionSummary(_ resolution: SpinLabDomain.RouteChannelResolution) -> String {
        var parts: [String] = []
        let sample = resolution.sampleKey ?? "unresolved"
        parts.append("\(resolution.channel) -> \(sample)")
        parts.append("[\(resolution.source)]")

        if !resolution.tags.isEmpty {
            parts.append("tags: \(resolution.tags.joined(separator: ", "))")
        }
        if let warning = resolution.warning {
            parts.append("warning: \(warning)")
        }
        return parts.joined(separator: " | ")
    }
}

private struct CreateProjectSheet: View {
    @EnvironmentObject private var appState: SpinLabAppState
    @Environment(\.dismiss) private var dismiss
    @State private var projectName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Project")
                .font(.title3.bold())

            EditableMetadataField(label: "Project Name", value: $projectName)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Create") {
                    if appState.createProject(named: projectName) != nil {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

private struct ImportedFileReviewSheet: View {
    let fileName: String
    @Binding var editableFileContents: String
    let hasEditableFileContents: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(fileName)
                .font(.title3.bold())
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if hasEditableFileContents {
                TextEditor(text: $editableFileContents)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("This imported file could not be loaded as editable text.")
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

private struct RegistryStatusColumn: View {
    @EnvironmentObject private var appState: SpinLabAppState

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
    @EnvironmentObject private var appState: SpinLabAppState

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
