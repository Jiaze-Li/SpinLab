import SwiftUI

struct LibrarySettingsSectionView: View {
    @Binding var isExpanded: Bool

    let library: LibraryFeatureStore

    let onChooseLibraryRoot: () -> Void
    let onVerifyRoot: () -> Void
    let onSyncFiles: () -> Void
    let onBackfillSidecars: () -> Void
    let onChooseBackupPath: () -> Void
    let onSyncBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CollapsibleSectionHeader(title: "Library Settings", isExpanded: $isExpanded)

            if isExpanded {
                GroupBox {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        MetadataValueRow(
                            label: "Library Root",
                            value: library.librarySettings.rootPath ?? "Not set",
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
                            .disabled(library.librarySettings.rootPath == nil)
                            Button("Recompute from Rules") {
                                onBackfillSidecars()
                            }
                            .disabled(library.librarySettings.rootPath == nil)
                        }

                        if let message = library.libraryRootVerificationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let path = library.libraryRootVerificationPath {
                            MetadataValueRow(label: "Verified Path", value: path, monospaced: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Library Root")
                        .font(AppFontScale.groupHeader)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        MetadataValueRow(
                            label: "Backup Path",
                            value: library.librarySettings.backupPath ?? "Not set",
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
                            .disabled(library.librarySettings.rootPath == nil || library.librarySettings.backupPath == nil)
                        }

                        if let error = library.libraryBackupError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let message = library.libraryBackupMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Backup")
                        .font(AppFontScale.groupHeader)
                }
            }
        }
    }
}

struct RegistryWorkspaceSectionView: View {
    @Binding var isExpanded: Bool
    @Binding var allowedPrefixesDraft: String

    let library: LibraryFeatureStore
    let canReloadSampleRegistry: Bool

    let selectedPrefix: String?
    let selectedBatchId: String?
    let selectedSampleId: String?
    let previewPrefixes: [String]
    let previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup]
    let selectedBatchSamples: [LibrarySample]

    let onLoadRegistry: () -> Void
    let onReloadRegistry: () -> Void
    let onSavePrefixes: (String) -> Void
    let onSelectPrefix: (String) -> Void
    let onSelectBatch: (LibraryPreviewBatchGroup) -> Void
    let onSelectSample: (LibrarySample) -> Void
    let onSyncRegistry: () -> Void
    let onApplyAll: () -> Void
    let onApplySelected: () -> Void

    let syncStatusSymbol: (LibrarySyncBatchStatus) -> String
    let syncStatusColor: (LibrarySyncBatchStatus) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CollapsibleSectionHeader(title: "Registry Operations", isExpanded: $isExpanded)

            if isExpanded {
                GroupBox {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        MetadataValueRow(
                            label: "Registry Path",
                            value: library.librarySettings.registrySourcePath ?? "Not loaded",
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
                            Button("Sync Registry") {
                                onSyncRegistry()
                            }
                            Spacer()
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
                            allowedPrefixesDraft = library.librarySettings.allowedBatchPrefixes.joined(separator: ", ")
                        }

                        if let message = library.libraryPreviewMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let message = library.libraryDrawerMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = library.libraryDrawerError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Registry")
                            .font(AppFontScale.groupHeader)
                        if let syncStatus = library.librarySyncStatusMessage {
                            Text("(\(syncStatus))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if let review = library.libraryRefreshReview {
                            HStack {
                                Button("Apply All") {
                                    onApplyAll()
                                }
                                .disabled(review.totalChangesCount == 0)
                                Button("Apply Selected") {
                                    onApplySelected()
                                }
                                .disabled(review.totalChangesCount == 0 || selectedBatchId == nil)
                            }
                        }

                        if !library.libraryPreviewWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(library.libraryPreviewWarnings) { warning in
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

                        prefixPicker
                        Divider()
                        batchList
                        Divider()
                        sampleList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack(spacing: 6) {
                        Text("Pending Queue")
                            .font(AppFontScale.groupHeader)
                        if let review = library.libraryRefreshReview {
                            Text("(\(review.newSamples.count) new, \(review.changedSamples.count) changed, \(review.removedSamples.count) removed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(previewGroupsForSelectedPrefix) { group in
                        Button {
                            onSelectBatch(group)
                        } label: {
                            BatchPreviewRow(
                                group: group,
                                isSelected: selectedBatchId == group.batchId,
                                status: library.libraryBatchSyncStatusByID[group.batchId],
                                syncStatusSymbol: syncStatusSymbol,
                                syncStatusColor: syncStatusColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
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
                LazyVStack(alignment: .leading, spacing: 2) {
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
                    }
                }
                .padding(.horizontal, 4)
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
    @Binding var thicknessToleranceText: String
    @Binding var oxygenToleranceText: String
    @Binding var temperatureToleranceText: String
    @Binding var energyToleranceText: String

    let searchHasExecuted: Bool
    let searchMatchedResults: [SearchResultItem]
    let onSearch: () -> Void
    let onClear: () -> Void
    let onSelectResult: (SearchResultItem) -> Void
    let isSelectedResult: (SearchResultItem) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CollapsibleSectionHeader(title: "Search", isExpanded: $isExpanded)

            if isExpanded {
                GroupBox {
                    searchOperationBox
                } label: {
                    Text("Search Conditions")
                        .font(AppFontScale.groupHeader)
                }

                GroupBox {
                    searchResultBox
                } label: {
                    Text("Search Result")
                        .font(AppFontScale.groupHeader)
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
                    numericInputRow(label: "厚度", text: $thicknessText, toleranceText: $thicknessToleranceText)
                    numericInputRow(label: "氧压", text: $oxygenText, toleranceText: $oxygenToleranceText)
                    numericInputRow(label: "温度", text: $temperatureText, toleranceText: $temperatureToleranceText)
                    numericInputRow(label: "能量", text: $energyText, toleranceText: $energyToleranceText)
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
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func numericInputRow(label: String, text: Binding<String>, toleranceText: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            TextField("value", text: text)
                .textFieldStyle(.roundedBorder)
            Text("±")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("tol", text: toleranceText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
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
