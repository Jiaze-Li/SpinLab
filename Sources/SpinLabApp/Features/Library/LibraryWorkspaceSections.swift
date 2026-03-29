import SwiftUI

struct LibrarySettingsSectionView: View {
    @Binding var isExpanded: Bool
    @Binding var allowedPrefixesDraft: String

    let level2HeaderFont: Font
    let level3HeaderFont: Font
    let viewState: LibraryViewState
    let canReloadSampleRegistry: Bool

    let onLoadRegistry: () -> Void
    let onReloadRegistry: () -> Void
    let onChooseLibraryRoot: () -> Void
    let onVerifyRoot: () -> Void
    let onSyncFiles: () -> Void
    let onSavePrefixes: (String) -> Void
    let onChooseBackupPath: () -> Void
    let onSyncBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Library Settings")
                        .font(level2HeaderFont)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Registry Path",
                            value: viewState.registrySourcePath ?? "Not loaded",
                            monospaced: true
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Load Registry") {
                                onLoadRegistry()
                            }
                            Button("Reload Registry") {
                                onReloadRegistry()
                            }
                            .disabled(!canReloadSampleRegistry)
                            Spacer()
                        }
                    }
                } label: {
                    Text("Registry")
                        .font(level3HeaderFont)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Library Root",
                            value: viewState.libraryRootPath ?? "Not set",
                            monospaced: true
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Choose Library Root") {
                                onChooseLibraryRoot()
                            }
                            Button("Verify Root") {
                                onVerifyRoot()
                            }
                            Button("Sync Files") {
                                onSyncFiles()
                            }
                            .disabled(viewState.libraryRootPath == nil)
                        }

                        if let message = viewState.rootVerificationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let path = viewState.rootVerificationPath {
                            MetadataValueRow(label: "Verified Path", value: path, monospaced: true)
                        }

                        HStack {
                            TextField("Allowed Prefixes (PN, PT, SL)", text: $allowedPrefixesDraft)
                                .frame(width: 190)
                                .textFieldStyle(.roundedBorder)
                            Button("Save Prefixes") {
                                onSavePrefixes(allowedPrefixesDraft)
                            }
                        }
                        .onAppear {
                            allowedPrefixesDraft = viewState.allowedBatchPrefixesText
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Library Root")
                        .font(level3HeaderFont)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Backup Path",
                            value: viewState.backupPath ?? "Not set",
                            monospaced: true
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Choose Backup Path") {
                                onChooseBackupPath()
                            }
                            Button("Sync Backup") {
                                onSyncBackup()
                            }
                            .disabled(viewState.libraryRootPath == nil || viewState.backupPath == nil)
                        }

                        if let error = viewState.backupError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let message = viewState.backupMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Backup")
                        .font(level3HeaderFont)
                }
            }
        }
    }
}

struct RegistryWorkspaceSectionView: View {
    @Binding var isExpanded: Bool

    let level2HeaderFont: Font
    let level3HeaderFont: Font
    let viewState: LibraryViewState

    let selectedPrefix: String?
    let selectedBatchId: String?
    let selectedSampleId: String?
    let previewPrefixes: [String]
    let previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup]
    let selectedBatchSamples: [LibrarySample]

    let onSelectPrefix: (String) -> Void
    let onSelectBatch: (LibraryPreviewBatchGroup) -> Void
    let onSelectSample: (LibrarySample) -> Void
    let onSyncRegistry: () -> Void
    let onApplyAll: () -> Void
    let onApplySelected: () -> Void

    let syncStatusSymbol: (LibrarySyncBatchStatus) -> String
    let syncStatusColor: (LibrarySyncBatchStatus) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Registry Operations")
                        .font(level2HeaderFont)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Sync Registry") {
                                onSyncRegistry()
                            }
                            Button("Apply All") {
                                onApplyAll()
                            }
                            .disabled((viewState.refreshReview?.totalChangesCount ?? 0) == 0)
                            Button("Apply Selected") {
                                onApplySelected()
                            }
                            .disabled((viewState.refreshReview?.totalChangesCount ?? 0) == 0 || selectedBatchId == nil)
                        }

                        if let message = viewState.previewMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let review = viewState.refreshReview {
                            Text("Pending sync review: \(review.newSamples.count) new, \(review.changedSamples.count) changed, \(review.removedSamples.count) removed, \(review.changedBatches.count) batch-changed, \(review.removedBatches.count) batch-removed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !viewState.previewWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewState.previewWarnings) { warning in
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

                        if let message = viewState.drawerMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = viewState.drawerError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack(spacing: 6) {
                        Text("Registry Sync")
                            .font(level3HeaderFont)
                        if let syncStatus = viewState.syncStatusMessage {
                            Text("(\(syncStatus))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        prefixPicker
                        Divider()
                        batchList
                        Divider()
                        sampleList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Pending Queue")
                        .font(level3HeaderFont)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        onSelectPrefix(newValue)
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
                List {
                    ForEach(previewGroupsForSelectedPrefix) { group in
                        Button {
                            onSelectBatch(group)
                        } label: {
                            BatchPreviewRow(
                                group: group,
                                isSelected: selectedBatchId == group.batchId,
                                status: viewState.batchSyncStatusByID[group.batchId],
                                syncStatusSymbol: syncStatusSymbol,
                                syncStatusColor: syncStatusColor
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
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
                List {
                    ForEach(selectedBatchSamples) { sample in
                        Button {
                            onSelectSample(sample)
                        } label: {
                            PreviewSampleRowContent(
                                sample: sample,
                                isSelected: selectedSampleId == sample.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .frame(height: 260)
            }
        }
    }
}

struct SearchWorkspaceSectionView: View {
    @Binding var isExpanded: Bool
    @Binding var batchIdText: String
    @Binding var substrateText: String
    @Binding var keywordText: String
    @Binding var thicknessText: String
    @Binding var oxygenText: String
    @Binding var temperatureText: String
    @Binding var energyText: String

    let level2HeaderFont: Font
    let level3HeaderFont: Font
    let searchHasExecuted: Bool
    let searchMatchedResults: [SearchResultItem]
    let onSearch: () -> Void
    let onClear: () -> Void
    let onSelectResult: (SearchResultItem) -> Void
    let isSelectedResult: (SearchResultItem) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text("Search")
                        .font(level2HeaderFont)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                GroupBox {
                    searchOperationBox
                } label: {
                    Text("Search Conditions")
                        .font(level3HeaderFont)
                }

                GroupBox {
                    searchResultBox
                } label: {
                    Text("Search Result")
                        .font(level3HeaderFont)
                }
            }
        }
    }

    private var searchOperationBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Conditions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    searchInputRow(label: "Batch ID", placeholder: "contains", text: $batchIdText)
                    searchInputRow(label: "Substrate Tags", placeholder: "contains", text: $substrateText)
                    searchInputRow(label: "Global Text", placeholder: "contains", text: $keywordText)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Numeric Conditions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    searchInputRow(label: "厚度", placeholder: "numeric", text: $thicknessText)
                    searchInputRow(label: "氧压", placeholder: "numeric", text: $oxygenText)
                    searchInputRow(label: "温度", placeholder: "numeric", text: $temperatureText)
                    searchInputRow(label: "能量", placeholder: "numeric", text: $energyText)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 8) {
                Button("Search") {
                    onSearch()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text("Rule: non-empty fields are AND conditions; empty fields are ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchResultBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !searchHasExecuted {
                Text("Set conditions and click Search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Matched samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(searchMatchedResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if searchMatchedResults.isEmpty {
                    Text("No matched sample")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(searchMatchedResults) { result in
                                Button {
                                    onSelectResult(result)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(result.sample.displayName)
                                            .font(.subheadline)
                                        Spacer()
                                        Text("\(result.prefix)/\(result.sample.batchId)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelectedResult(result) ? Color.accentColor.opacity(0.15) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchInputRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct BatchPreviewRow: View {
    let group: LibraryPreviewBatchGroup
    let isSelected: Bool
    let status: LibrarySyncBatchStatus?
    let syncStatusSymbol: (LibrarySyncBatchStatus) -> String
    let syncStatusColor: (LibrarySyncBatchStatus) -> Color

    var body: some View {
        HStack {
            if let status, status != .unchanged {
                if status == .added {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.green)
                } else if status == .removed {
                    Image(systemName: "minus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.red)
                } else {
                    Image(systemName: syncStatusSymbol(status))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(syncStatusColor(status))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct PreviewSampleRowContent: View {
    let sample: LibrarySample
    let isSelected: Bool

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
    }
}
