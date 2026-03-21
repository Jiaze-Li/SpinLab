import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var appState: SpinLabAppState
    @State private var allowedPrefixesDraft: String = ""
    @State private var selectedPrefix: String?
    @State private var selectedBatchId: String?
    @State private var selectedSampleId: String?
    @State private var isRegistryWorkspaceExpanded = true

    var body: some View {
        HSplitView {
            librarySettingsColumn
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 680)
                .layoutPriority(1)

            libraryDetailColumn
                .frame(minWidth: 320, idealWidth: 500, maxWidth: .infinity)
                .layoutPriority(0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncSelection()
        }
        .onChange(of: appState.libraryPreviewGroups) { _, _ in
            syncSelection()
        }
    }

    private var librarySettingsColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Library")
                    .font(.title2.bold())

                librarySettingsSection
                registryWorkspaceSection
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .animation(nil, value: selectedBatchId)
        .animation(nil, value: selectedSampleId)
    }

    private var librarySettingsSection: some View {
        GroupBox("Library Settings") {
            VStack(alignment: .leading, spacing: 8) {
                MetadataValueRow(
                    label: "Registry Path (Inbox)",
                    value: appState.librarySettings.registrySourcePath ?? appState.registrySourceFilePath ?? "Not loaded",
                    monospaced: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

                MetadataValueRow(
                    label: "Library Root",
                    value: appState.librarySettings.rootPath ?? "Not set",
                    monospaced: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Choose Library Root") {
                        presentLibraryRootPanel()
                    }
                    Button("Verify Root") {
                        appState.verifyLibraryRoot()
                    }
                    Button("Sync Files") {
                        appState.syncLibraryFromFiles()
                    }
                    .disabled(appState.librarySettings.rootPath == nil)
                }

                if let message = appState.libraryRootVerificationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let path = appState.libraryRootVerificationPath {
                    MetadataValueRow(label: "Verified Path", value: path, monospaced: true)
                }

                HStack {
                    TextField("Allowed Prefixes (PN, PT, SL)", text: $allowedPrefixesDraft)
                        .frame(width: 190)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Prefixes") {
                        appState.updateAllowedBatchPrefixes(from: allowedPrefixesDraft)
                    }
                }
                .onAppear {
                    allowedPrefixesDraft = appState.librarySettings.allowedBatchPrefixes.joined(separator: ", ")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var registryWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isRegistryWorkspaceExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRegistryWorkspaceExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Registry Operations (XLSX Aligned)")
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRegistryWorkspaceExpanded {
                registryPreviewSection
                registryBrowserSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var registryPreviewSection: some View {
        GroupBox {
            registryPreviewSectionContent
        } label: {
            registryPreviewSectionLabel
        }
    }

    private var registryPreviewSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Sync Registry") {
                    appState.syncLibraryFromRegistry()
                }
                Button("Apply All") {
                    appState.applyPreparedLibrarySyncReview()
                }
                .disabled((appState.libraryRefreshReview?.totalChangesCount ?? 0) == 0)
                Button("Apply Selected") {
                    appState.applySelectedRegistryDiff(batchId: selectedBatchId)
                }
                .disabled((appState.libraryRefreshReview?.totalChangesCount ?? 0) == 0 || selectedBatchId == nil)
            }

            if let message = appState.libraryPreviewMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let review = appState.libraryRefreshReview {
                Text("Pending sync review: \(review.newSamples.count) new, \(review.changedSamples.count) changed, \(review.removedSamples.count) removed, \(review.changedBatches.count) batch-changed, \(review.removedBatches.count) batch-removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.libraryPreviewWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.libraryPreviewWarnings) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(warning.severity == .error ? Color.red : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(warning.message)
                                .font(.caption)
                        }
                    }
                }
            }

            if let message = appState.libraryDrawerMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = appState.libraryDrawerError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var registryPreviewSectionLabel: some View {
        HStack(spacing: 6) {
            Text("Registry Sync")
            if let syncStatus = appState.librarySyncStatusMessage {
                Text("(\(syncStatus))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var registryBrowserSection: some View {
        GroupBox("Pending Queue") {
            VStack(alignment: .leading, spacing: 8) {
                prefixPicker
                Divider()
                batchList
                Divider()
                sampleList
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var prefixPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prefix")
                .font(.caption)
                .foregroundStyle(.secondary)

            if previewPrefixes.isEmpty {
                Text("Load preview to select prefix")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Prefix", selection: Binding(
                    get: { selectedPrefix ?? previewPrefixes.first ?? "" },
                    set: { newValue in
                        selectedPrefix = newValue
                        selectedBatchId = previewGroupsForSelectedPrefix.first?.batchId
                        selectedSampleId = previewGroupsForSelectedPrefix.first?.samples.first?.id
                        appState.selectBrowserSample()
                    })
                ) {
                    ForEach(previewPrefixes, id: \.self) { prefix in
                        Text(prefix).tag(prefix)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180, alignment: .leading)
            }
        }
    }

    private var batchList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Batch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(previewGroupsForSelectedPrefix.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if previewGroupsForSelectedPrefix.isEmpty {
                Text("No batch available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(previewGroupsForSelectedPrefix) { group in
                            Button {
                                selectedBatchId = group.batchId
                                selectedSampleId = group.samples.first?.id
                                appState.selectBrowserSample()
                            } label: {
                                HStack {
                                    if let status = appState.libraryBatchSyncStatusByID[group.batchId], status != .unchanged {
                                        if status == .added {
                                            Image(systemName: "plus")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(Color.green)
                                        } else if status == .removed {
                                            Image(systemName: "minus")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(Color.red)
                                        } else {
                                            Image(systemName: syncStatusSymbol(for: status))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(syncStatusColor(for: status))
                                        }
                                    }
                                    Text(group.batchId)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(group.samples.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedBatchId == group.batchId ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var sampleList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Physical Sample")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedBatchSamples.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedBatchSamples.isEmpty {
                Text("Select a batch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(selectedBatchSamples) { sample in
                            PreviewSampleRow(
                                sample: sample,
                                isSelected: selectedSampleId == sample.id
                            ) {
                                selectedSampleId = sample.id
                                appState.selectBrowserSample()
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
        }
    }

    private var libraryDetailColumn: some View {
        GeometryReader { proxy in
            let detailWidth = proxy.size.width
            let detailHeight = proxy.size.height
            let sectionWidth = max(detailWidth - 24, 0)
            let sectionSpacing = adaptiveDetailSectionSpacing(for: detailHeight)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    Text("Sample Detail")
                        .font(.title2.bold())

                    if let sample = selectedSample {
                        let sections = makeDetailSections(for: sample)
                        let globalFirstColumnWidth = alignedFirstColumnWidth(
                            fields: sections.allFields,
                            availableWidth: sectionWidth
                        )

                        detailSection(
                            fields: sections.sampleFields,
                            availableWidth: sectionWidth,
                            sharedFirstColumnWidth: globalFirstColumnWidth
                        )

                        if !selectedChangeHighlights(for: sample).isEmpty {
                            Divider()
                            Text("Pending Changes")
                                .font(.headline)
                            pendingChangesSection(for: sample)
                        }

                        if !sections.substrateFields.isEmpty {
                            detailSection(
                                fields: sections.substrateFields,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )
                        }

                        if !sections.numericFields.isEmpty {
                            Divider()
                            Text("Numeric Tags")
                                .font(.headline)
                            detailSection(
                                fields: sections.numericFields,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )
                        }

                        Divider()
                        Text("Metadata")
                            .font(.headline)
                        if sample.orderedMetadata.isEmpty {
                            Text("No metadata")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            detailSection(
                                fields: sections.metadataFields,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "No Sample Selected",
                            systemImage: "tray",
                            description: Text("Select a prefix, batch, and sample to view metadata.")
                        )
                    }
                }
                .frame(minHeight: max(detailHeight - 8, 0), alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func detailSection(
        fields: [DetailField],
        availableWidth: CGFloat,
        sharedFirstColumnWidth: CGFloat?
    ) -> some View {
        let rows = groupedFields(fields)
        let sectionFirstColumnWidth = sharedFirstColumnWidth ?? sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                if row.count == 1 {
                    detailFieldRow(row[0], fillWidth: true)
                } else if let firstWidth = sectionFirstColumnWidth {
                    HStack(alignment: .top, spacing: 12) {
                        detailFieldRow(row[0], fixedWidth: firstWidth, fillWidth: false)
                        detailFieldRow(row[1], fillWidth: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        detailFieldRow(row[0], fillWidth: true)
                        detailFieldRow(row[1], fillWidth: true)
                    }
                }
            }
        }
    }

    private func alignedFirstColumnWidth(fields: [DetailField], availableWidth: CGFloat) -> CGFloat? {
        let rows = groupedFields(fields)
        return sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
    }

    private func groupedFields(_ fields: [DetailField]) -> [[DetailField]] {
        var rows: [[DetailField]] = []
        var pending: DetailField?
        for field in fields {
            if field.fullWidth {
                if let pendingField = pending {
                    rows.append([pendingField])
                    pending = nil
                }
                rows.append([field])
                continue
            }
            if let pendingField = pending {
                rows.append([pendingField, field])
                pending = nil
            } else {
                pending = field
            }
        }
        if let pendingField = pending {
            rows.append([pendingField])
        }
        return rows
    }

    @ViewBuilder
    private func detailFieldRow(_ field: DetailField, fixedWidth: CGFloat? = nil, fillWidth: Bool) -> some View {
        let row = MetadataValueRow(label: field.label, value: field.value, monospaced: field.monospaced)
        if let fixedWidth {
            row
                .frame(width: fixedWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else if fillWidth {
            row
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            row
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionFirstColumnWidth(rows: [[DetailField]], availableWidth: CGFloat) -> CGFloat? {
        twoColumnWidths(rows: rows, availableWidth: availableWidth)?.first
    }

    private func twoColumnWidths(rows: [[DetailField]], availableWidth: CGFloat) -> (first: CGFloat, second: CGFloat)? {
        let spacing: CGFloat = 12
        let minColumnWidth: CGFloat = 170
        let firstColumnMaxWidth: CGFloat = 420

        let pairRows = rows.filter { $0.count == 2 }
        guard !pairRows.isEmpty else {
            return nil
        }

        // Character-based redundancy: reserve extra breathing room equivalent to 5 chars.
        let redundancyInChars: CGFloat = 5
        let averageCharWidth = estimatedTextWidth("MMMMM", font: .systemFont(ofSize: NSFont.systemFontSize)) / 5
        let redundancyWidth = max(averageCharWidth * redundancyInChars, 24)

        let firstContentNeeded = pairRows
            .map { estimatedFieldWidth($0[0]) }
            .max() ?? minColumnWidth
        let secondContentNeeded = pairRows
            .map { estimatedFieldWidth($0[1]) }
            .max() ?? minColumnWidth

        let firstBase = max(firstContentNeeded + redundancyWidth, minColumnWidth)
        let secondBase = max(secondContentNeeded + redundancyWidth, minColumnWidth)
        let totalBase = firstBase + secondBase + spacing

        // If the total width is insufficient, fallback to single-column rendering.
        guard availableWidth >= totalBase else {
            return nil
        }

        let extra = availableWidth - totalBase
        var first = firstBase + extra / 2
        var second = secondBase + extra / 2

        // Cap the first column in wide layouts to avoid visual imbalance.
        if first > firstColumnMaxWidth {
            let overflow = first - firstColumnMaxWidth
            first = firstColumnMaxWidth
            second += overflow
        }

        // Keep the second column at least minimally readable.
        if second < minColumnWidth {
            let needed = minColumnWidth - second
            first -= needed
            second = minColumnWidth
        }

        let maxFirstGivenAvailable = availableWidth - minColumnWidth - spacing
        first = min(first, maxFirstGivenAvailable)
        second = availableWidth - first - spacing
        guard first >= minColumnWidth, second >= minColumnWidth else {
            return nil
        }
        return (first: first, second: second)
    }

    private func estimatedFieldWidth(_ field: DetailField) -> CGFloat {
        let labelWidth = estimatedTextWidth(field.label, font: .systemFont(ofSize: NSFont.smallSystemFontSize))
        let valueFont: NSFont = field.monospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        let valueWidth = estimatedTextWidth(field.value, font: valueFont)
        let clampedValueWidth = min(max(valueWidth, 80), 360)
        return max(labelWidth, clampedValueWidth)
    }

    private func estimatedTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let sample = text.isEmpty ? " " : text
        let singleLine = sample
            .split(separator: "\n")
            .map(String.init)
            .max(by: { $0.count < $1.count }) ?? sample
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((singleLine as NSString).size(withAttributes: attributes).width)
    }

    private func isLongField(_ value: String) -> Bool {
        if value.count > 68 {
            return true
        }
        let markers = ["/", "\\", "\n", "\t"]
        return markers.contains { value.contains($0) } && value.count > 34
    }

    private func orderedNumericTagKeys(for sample: LibrarySample) -> [String] {
        let preferred = ["厚度", "氧压", "温度", "能量", "电压", "磁场", "电阻"]
        var keys: [String] = []
        for key in preferred where sample.numericDisplay[key] != nil {
            keys.append(key)
        }
        for key in sample.numericDisplay.keys where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    private func adaptiveDetailSectionSpacing(for height: CGFloat) -> CGFloat {
        let base: CGFloat = 12
        let extraHeight = max(height - 720, 0)
        // Spread sections out on tall windows while keeping dense layout on normal heights.
        return min(base + extraHeight / 28, 26)
    }

    @ViewBuilder
    private func pendingChangesSection(for sample: LibrarySample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(selectedChangeHighlights(for: sample)) { change in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.key)
                            .font(.caption.weight(.semibold))
                        Text(change.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow.opacity(0.45), lineWidth: 0.8)
                )
            }
        }
    }

    private func selectedChangeHighlights(for sample: LibrarySample) -> [ChangeHighlight] {
        let sampleChanges = appState.librarySampleSyncChangesByID[sample.id] ?? []
        let batchChanges = appState.libraryBatchSyncChangesByID[sample.batchId] ?? []
        let sampleHighlights = sampleChanges.map {
            ChangeHighlight(key: $0.key, description: "\(displayValue($0.oldValue)) -> \(displayValue($0.newValue))")
        }
        let batchHighlights = batchChanges.map {
            ChangeHighlight(key: "Batch.\($0.key)", description: "\(displayValue($0.oldValue)) -> \(displayValue($0.newValue))")
        }
        return sampleHighlights + batchHighlights
    }

    private func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : "∅"
    }

    private func syncStatusSymbol(for status: LibrarySyncBatchStatus) -> String {
        switch status {
        case .added:
            return "plus.circle.fill"
        case .changed:
            return "circle.fill"
        case .removed:
            return "minus.circle.fill"
        case .unchanged:
            return "circle"
        }
    }

    private func syncStatusColor(for status: LibrarySyncBatchStatus) -> Color {
        switch status {
        case .added:
            return .green
        case .changed:
            return .yellow
        case .removed:
            return .red
        case .unchanged:
            return .secondary
        }
    }

    private var previewPrefixes: [String] {
        let configured = appState.librarySettings.allowedBatchPrefixes.map { $0.uppercased() }
        let available = Array(combinedPreviewGroupsByPrefix.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    private var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] {
        let prefix = selectedPrefix ?? previewPrefixes.first
        return combinedPreviewGroupsByPrefix[prefix ?? ""] ?? []
    }

    private var combinedPreviewGroupsByPrefix: [String: [LibraryPreviewBatchGroup]] {
        var groups = appState.libraryPreviewGroups
        for (batchID, status) in appState.libraryBatchSyncStatusByID where status != .unchanged {
            let prefix = LibrarySort.batchSortKey(batchID).prefix
            let alreadyExists = groups[prefix]?.contains(where: { $0.batchId == batchID }) == true
            if alreadyExists {
                continue
            }
            let existingSamples = appState.libraryExistingGroups[prefix]?
                .first(where: { $0.batchId == batchID })?
                .samples ?? []
            groups[prefix, default: []].append(
                LibraryPreviewBatchGroup(batchId: batchID, samples: existingSamples)
            )
        }
        for prefix in groups.keys {
            groups[prefix] = groups[prefix]?.sorted { LibrarySort.compareBatch($0.batchId, $1.batchId) }
        }
        return groups
    }

    private var selectedBatchSamples: [LibrarySample] {
        guard let batchId = selectedBatchId else {
            return []
        }
        return previewGroupsForSelectedPrefix.first(where: { $0.batchId == batchId })?.samples ?? []
    }

    private var selectedSample: LibrarySample? {
        resolveSelectedSample(from: selectionEntry)
    }

    private var selectedExistingSample: LibrarySample? {
        guard let prefix = appState.librarySelectedPrefix,
              let batchId = appState.librarySelectedBatchId,
              let sampleId = appState.librarySelectedSampleId else {
            return nil
        }
        let groups = appState.libraryExistingGroups[prefix] ?? []
        let samples = groups.first(where: { $0.batchId == batchId })?.samples ?? []
        return samples.first(where: { $0.id == sampleId })
    }

    private func presentLibraryRootPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Library Root"
        panel.message = "Select a folder for the SpinLab library store."
        if panel.runModal() == .OK, let url = panel.url {
            appState.updateLibraryRoot(to: url)
        }
    }

    private func syncSelection() {
        if selectedPrefix == nil || !previewPrefixes.contains(selectedPrefix ?? "") {
            selectedPrefix = previewPrefixes.first
        }
        if let firstBatch = previewGroupsForSelectedPrefix.first?.batchId {
            if selectedBatchId == nil || previewGroupsForSelectedPrefix.first(where: { $0.batchId == selectedBatchId }) == nil {
                selectedBatchId = firstBatch
            }
        } else {
            selectedBatchId = nil
            selectedSampleId = nil
            return
        }
        if selectedSampleId == nil || !selectedBatchSamples.contains(where: { $0.id == selectedSampleId }) {
            selectedSampleId = selectedBatchSamples.first?.id
        }
    }

    private var selectionEntry: SelectionEntry {
        SelectionEntry(
            source: appState.libraryActiveSelectionSource,
            browserSampleId: selectedSampleId,
            drawerPrefix: appState.librarySelectedPrefix,
            drawerBatchId: appState.librarySelectedBatchId,
            drawerSampleId: appState.librarySelectedSampleId
        )
    }

    private func resolveSelectedSample(from entry: SelectionEntry) -> LibrarySample? {
        switch entry.source {
        case .browser:
            guard let sampleId = entry.browserSampleId else {
                return nil
            }
            return selectedBatchSamples.first(where: { $0.id == sampleId })
        case .drawer:
            return selectedExistingSample
        }
    }

    private func makeDetailSections(for sample: LibrarySample) -> SampleDetailSections {
        let sampleFields: [DetailField] = [
            DetailField(label: "Sample", value: sample.displayName, fullWidth: isLongField(sample.displayName)),
            DetailField(label: "Batch", value: sample.batchId),
            DetailField(label: "Sample Key", value: sample.id, monospaced: true, fullWidth: true),
            DetailField(label: "Substrate", value: sample.substrateDisplay)
        ]
        let substrateFields: [DetailField] = sample.substrateTags.isEmpty
            ? []
            : [DetailField(label: "Substrate Tags", value: sample.substrateTags.joined(separator: ", "), fullWidth: true)]
        let numericFields: [DetailField] = orderedNumericTagKeys(for: sample).map { key in
            DetailField(label: key, value: sample.numericDisplay[key] ?? "")
        }
        let metadataFields: [DetailField] = sample.orderedMetadata.map { item in
            DetailField(label: item.key, value: item.value, fullWidth: isLongField(item.value))
        }
        return SampleDetailSections(
            sampleFields: sampleFields,
            substrateFields: substrateFields,
            numericFields: numericFields,
            metadataFields: metadataFields
        )
    }
}

private struct SelectionEntry {
    let source: LibrarySelectionSource
    let browserSampleId: String?
    let drawerPrefix: String?
    let drawerBatchId: String?
    let drawerSampleId: String?
}

private struct SampleDetailSections {
    let sampleFields: [DetailField]
    let substrateFields: [DetailField]
    let numericFields: [DetailField]
    let metadataFields: [DetailField]

    var allFields: [DetailField] {
        sampleFields + substrateFields + numericFields + metadataFields
    }
}

private struct ChangeHighlight: Identifiable, Hashable {
    var id: String { "\(key)|\(description)" }
    let key: String
    let description: String
}

private struct DetailField: Hashable {
    let label: String
    let value: String
    var monospaced: Bool = false
    var fullWidth: Bool = false
}

private struct PreviewSampleRow: View, Equatable {
    let sample: LibrarySample
    let isSelected: Bool
    let onSelect: () -> Void

    static func == (lhs: PreviewSampleRow, rhs: PreviewSampleRow) -> Bool {
        lhs.sample.id == rhs.sample.id && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sample.substrateDisplay)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
