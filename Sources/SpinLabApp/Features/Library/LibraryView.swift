import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var appState: SpinLabAppState
    @State private var allowedPrefixesDraft: String = ""
    @State private var selectedPrefix: String?
    @State private var selectedBatchId: String?
    @State private var selectedSampleId: String?
    @State private var isPresentingCreateDrawers = false
    @State private var isPresentingCreateSelectedDrawers = false

    var body: some View {
        HSplitView {
            librarySettingsColumn
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 680)
                .layoutPriority(1)

            libraryDetailColumn
                .frame(minWidth: 320, idealWidth: 500, maxWidth: .infinity)
                .layoutPriority(0)
        }
        .padding(16)
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

                GroupBox("Registry Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Load Preview") {
                                appState.loadLibraryPreview()
                            }
                            Button("Create Drawers") {
                                isPresentingCreateDrawers = true
                            }
                            .disabled(appState.libraryPreview == nil || appState.librarySettings.rootPath == nil)
                            Button("Create Selected") {
                                isPresentingCreateSelectedDrawers = true
                            }
                            .disabled(appState.libraryPreview == nil || appState.librarySettings.rootPath == nil || selectedBatchId == nil)
                            if let message = appState.libraryPreviewMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

                GroupBox("Registry Browser") {
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
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .animation(nil, value: selectedBatchId)
        .animation(nil, value: selectedSampleId)
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
        .confirmationDialog(
            "Create Library Drawers?",
            isPresented: $isPresentingCreateDrawers,
            titleVisibility: .visible
        ) {
            Button("Create Drawers", role: .destructive) {
                appState.createDrawersFromPreview()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let count = appState.libraryPreview?.index.samples.count ?? 0
            let root = appState.librarySettings.rootPath ?? "Not set"
            Text("Create \(count) drawers under: \(root)")
        }
        .confirmationDialog(
            "Create Selected Drawers?",
            isPresented: $isPresentingCreateSelectedDrawers,
            titleVisibility: .visible
        ) {
            Button("Create Selected", role: .destructive) {
                appState.createDrawersForSelection(batchId: selectedBatchId, sampleId: selectedSampleId)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            let root = appState.librarySettings.rootPath ?? "Not set"
            let target = selectedSample?.displayName ?? selectedBatchId ?? "Selection"
            Text("Create drawers for: \(target)\nRoot: \(root)")
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
                            } label: {
                                HStack {
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
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sample Detail")
                        .font(.title2.bold())

                    if let sample = selectedSample {
                        detailSection(
                            fields: [
                                DetailField(label: "Sample", value: sample.displayName, fullWidth: isLongField(sample.displayName)),
                                DetailField(label: "Batch", value: sample.batchId),
                                DetailField(label: "Sample Key", value: sample.id, monospaced: true, fullWidth: true),
                                DetailField(label: "Substrate", value: sample.substrateDisplay)
                            ],
                            availableWidth: max(detailWidth - 24, 0)
                        )

                        if !sample.substrateTags.isEmpty {
                            detailSection(
                                fields: [DetailField(label: "Substrate Tags", value: sample.substrateTags.joined(separator: ", "), fullWidth: true)],
                                availableWidth: max(detailWidth - 24, 0)
                            )
                        }

                        if !sample.numericDisplay.isEmpty {
                            Divider()
                            Text("Numeric Tags")
                                .font(.headline)
                            detailSection(
                                fields: orderedNumericTagKeys(for: sample).map { key in
                                    DetailField(label: key, value: sample.numericDisplay[key] ?? "")
                                },
                                availableWidth: max(detailWidth - 24, 0)
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
                                fields: sample.orderedMetadata.map { item in
                                    DetailField(label: item.key, value: item.value, fullWidth: isLongField(item.value))
                                },
                                availableWidth: max(detailWidth - 24, 0)
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func detailSection(fields: [DetailField], availableWidth: CGFloat) -> some View {
        let rows = groupedFields(fields)
        let sectionFirstColumnWidth = sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
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
        let spacing: CGFloat = 12
        let minColumnWidth: CGFloat = 170
        let minTrailingWhitespaceAfterFirst: CGFloat = 28

        let pairRows = rows.filter { $0.count == 2 }
        guard !pairRows.isEmpty else {
            return nil
        }
        guard availableWidth >= (minColumnWidth * 2 + spacing) else {
            return nil
        }

        let maxFirstNeeded = pairRows
            .map { estimatedFieldWidth($0[0]) }
            .max() ?? minColumnWidth
        let maximumFirstWidth = max(minColumnWidth, availableWidth - minColumnWidth - spacing)
        let proposedFirstWidth = min(
            max(maxFirstNeeded + minTrailingWhitespaceAfterFirst, minColumnWidth),
            maximumFirstWidth
        )
        let remainingWidth = availableWidth - proposedFirstWidth - spacing
        guard remainingWidth >= minColumnWidth else {
            return nil
        }
        return proposedFirstWidth
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

    private var previewPrefixes: [String] {
        let configured = appState.librarySettings.allowedBatchPrefixes.map { $0.uppercased() }
        let available = Array(appState.libraryPreviewGroups.keys).sorted()
        if configured.isEmpty {
            return available
        }
        let ordered = configured.filter { available.contains($0) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    private var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] {
        let prefix = selectedPrefix ?? previewPrefixes.first
        return appState.libraryPreviewGroups[prefix ?? ""] ?? []
    }

    private var selectedBatchSamples: [LibrarySample] {
        guard let batchId = selectedBatchId else {
            return []
        }
        return previewGroupsForSelectedPrefix.first(where: { $0.batchId == batchId })?.samples ?? []
    }

    private var selectedSample: LibrarySample? {
        guard let sampleId = selectedSampleId else {
            return nil
        }
        return selectedBatchSamples.first(where: { $0.id == sampleId })
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
        if let prefix = selectedPrefix,
           let firstBatch = appState.libraryPreviewGroups[prefix]?.first?.batchId {
            if selectedBatchId == nil || previewGroupsForSelectedPrefix.first(where: { $0.batchId == selectedBatchId }) == nil {
                selectedBatchId = firstBatch
            }
        }
        if selectedSampleId == nil {
            selectedSampleId = selectedBatchSamples.first?.id
        }
    }
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
