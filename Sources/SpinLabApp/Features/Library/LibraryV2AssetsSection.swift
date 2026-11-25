import SwiftUI

struct LibraryV2AssetsSection: View {
    @Environment(SpinLabAppState.self) private var appState
    let sample: LibrarySample

    @State private var sourceGroups: [SampleSourceGroup] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var loadedAFMByDatasetID: [String: Result<LoadedDataset<CanonicalAFMDataset>, Error>] = [:]
    @State private var expandedSourceIDs: Set<String> = []
    @State private var confirmationContext: DeletionConfirmationContext?
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text("Measurements")
                    .font(AppFontScale.sectionHeader)
                Spacer()
                Button("Refresh") {
                    reloadToken += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let loadError {
                Text(loadError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if loadError == nil && sourceGroups.isEmpty {
                Text("No measurements recorded for this sample.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sourceGroups, id: \.source.id) { group in
                    sourceGroupCard(group)
                }
            }
        }
        .onAppear { reloadAssets() }
        .onChange(of: sample.id) { _, _ in reloadAssets() }
        .onChange(of: reloadToken) { _, _ in reloadAssets() }
        .sheet(item: $confirmationContext) { context in
            LibraryDeletionConfirmationSheet(context: context)
        }
    }

    @ViewBuilder
    private func sourceGroupCard(_ group: SampleSourceGroup) -> some View {
        let title = displayTitle(for: group.source)
        let workflowLabel = friendlyWorkflowLabel(for: group.source.format)
        let isExpanded = Binding(
            get: { expandedSourceIDs.contains(group.source.id) },
            set: { expanded in
                if expanded {
                    expandedSourceIDs.insert(group.source.id)
                } else {
                    expandedSourceIDs.remove(group.source.id)
                }
            }
        )

        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        HStack(spacing: AppSpacing.sm) {
                            Text(title)
                                .font(AppFontScale.groupHeader)
                            Text(workflowLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        if let summary = primarySummary(for: group) {
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if appState.library.canMutateLibraryDetailSelection {
                        Button(role: .destructive) {
                            beginDeleteSource(group)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Delete measurement \(title)")
                    }
                }

                if let issue = sourceOrDatasetIssue(for: group) {
                    Text(issue)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup("Details", isExpanded: isExpanded) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Grid(alignment: .leading, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.xs) {
                            detailRow("Source ID", group.source.id, monospaced: true)
                            detailRow("Source format", group.source.format, monospaced: true)
                            if let filename = group.source.originalFilename, !filename.isEmpty {
                                detailRow("Original file", filename, monospaced: false)
                            }
                        }

                        if group.datasets.isEmpty {
                            Text("No standardized datasets registered for this source.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(group.datasets, id: \.id) { dataset in
                                datasetDetailBlock(dataset, canDeleteIndividually: group.datasets.count > 1, sourceTitle: title)
                            }
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func datasetDetailBlock(_ dataset: AssetRecord, canDeleteIndividually: Bool, sourceTitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Divider()
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                Text(dataset.id)
                    .font(.callout.monospaced())
                Text("rev \(dataset.currentRevision)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if canDeleteIndividually && appState.library.canMutateLibraryDetailSelection {
                    Button("Delete Dataset") {
                        beginDeleteDataset(dataset, sourceTitle: sourceTitle)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }

            if dataset.format == AFMDatasetCodec.format {
                afmDatasetDetails(for: dataset.id)
            } else {
                Text("Format: \(dataset.format)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func afmDatasetDetails(for datasetID: String) -> some View {
        switch loadedAFMByDatasetID[datasetID] {
        case .none:
            EmptyView()
        case let .some(.failure(error)):
            Text("Dataset read error: \(error.localizedDescription)")
                .font(.callout)
                .foregroundStyle(.red)
        case let .some(.success(loaded)):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if loaded.sourceAvailability != .available {
                    Text("Source status: \(sourceAvailabilityLabel(loaded.sourceAvailability))")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                let cols = loaded.dataset.xCoordinates.count
                let rows = loaded.dataset.yCoordinates.count
                ForEach(loaded.dataset.channels, id: \.id) { channel in
                    let unit = channel.canonicalUnit.isEmpty ? "unknown" : channel.canonicalUnit
                    let sourceUnit = channel.sourceUnit.isEmpty ? "unknown" : channel.sourceUnit
                    Text("• \(channel.displayLabel) [\(unit), source: \(sourceUnit)] (\(rows)×\(cols))")
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String, monospaced: Bool) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
        }
    }

    private func displayTitle(for source: AssetRecord) -> String {
        if let filename = source.originalFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
           !filename.isEmpty {
            return filename
        }
        return "Measurement"
    }

    private func friendlyWorkflowLabel(for format: String) -> String {
        if format == AFMIBWStandardizationAdapter.formatID || format.hasPrefix("afm-") {
            return "AFM"
        }
        return format
    }

    private func primarySummary(for group: SampleSourceGroup) -> String? {
        if group.datasets.isEmpty {
            return "No standardized datasets"
        }
        if group.datasets.count == 1, let dataset = group.datasets.first,
           case let .some(.success(loaded)) = loadedAFMByDatasetID[dataset.id] {
            let cols = loaded.dataset.xCoordinates.count
            let rows = loaded.dataset.yCoordinates.count
            let channelNames = loaded.dataset.channels.map(\.displayLabel).joined(separator: ", ")
            if channelNames.isEmpty {
                return "\(rows)×\(cols)"
            }
            return "\(loaded.dataset.channels.count) channel(s) (\(channelNames)) · \(rows)×\(cols)"
        }
        return "\(group.datasets.count) dataset(s)"
    }

    private func sourceOrDatasetIssue(for group: SampleSourceGroup) -> String? {
        for dataset in group.datasets {
            switch loadedAFMByDatasetID[dataset.id] {
            case let .some(.failure(error)):
                return "Read error: \(error.localizedDescription)"
            case let .some(.success(loaded)) where loaded.sourceAvailability != .available:
                return "Source \(sourceAvailabilityLabel(loaded.sourceAvailability))"
            default:
                continue
            }
        }
        return nil
    }

    private func sourceAvailabilityLabel(_ availability: SourceAvailability) -> String {
        switch availability {
        case .available:
            return "available"
        case .missing:
            return "missing"
        case let .corrupt(reason):
            return "corrupt (\(reason))"
        }
    }

    private func beginDeleteSource(_ group: SampleSourceGroup) {
        actionError = nil
        let target = LibraryAssetService.AssetDeletionTarget.source(group.source.id)
        switch appState.planV2AssetDeletion(target: target) {
        case let .success(plan):
            confirmationContext = DeletionConfirmationContext(
                kind: .measurement(
                    title: displayTitle(for: group.source),
                    datasetCount: group.datasets.count,
                    isSingleDataset: false,
                    plan: plan
                ),
                onConfirm: {
                    switch appState.commitV2AssetDeletion(
                        target: target,
                        plan: plan,
                        operationPrefix: "delete-source-\(group.source.id)"
                    ) {
                    case .success:
                        reloadToken += 1
                    case let .failure(error):
                        actionError = error.localizedDescription
                    }
                },
                onCancel: {}
            )
        case let .failure(error):
            actionError = error.localizedDescription
        }
    }

    private func beginDeleteDataset(_ dataset: AssetRecord, sourceTitle: String) {
        actionError = nil
        let target = LibraryAssetService.AssetDeletionTarget.dataset(dataset.id)
        switch appState.planV2AssetDeletion(target: target) {
        case let .success(plan):
            confirmationContext = DeletionConfirmationContext(
                kind: .measurement(
                    title: sourceTitle,
                    datasetCount: 1,
                    isSingleDataset: true,
                    plan: plan
                ),
                onConfirm: {
                    switch appState.commitV2AssetDeletion(
                        target: target,
                        plan: plan,
                        operationPrefix: "delete-dataset-\(dataset.id)"
                    ) {
                    case .success:
                        reloadToken += 1
                    case let .failure(error):
                        actionError = error.localizedDescription
                    }
                },
                onCancel: {}
            )
        case let .failure(error):
            actionError = error.localizedDescription
        }
    }

    private func reloadAssets() {
        loadError = nil
        switch appState.loadV2SourceGroups(for: sample) {
        case let .failure(error):
            sourceGroups = []
            loadedAFMByDatasetID = [:]
            loadError = error.localizedDescription
        case let .success(groups):
            sourceGroups = groups
            var datasets: [String: Result<LoadedDataset<CanonicalAFMDataset>, Error>] = [:]
            for group in groups {
                for dataset in group.datasets where dataset.format == AFMDatasetCodec.format {
                    datasets[dataset.id] = appState.loadV2AFMDataset(datasetID: dataset.id)
                }
            }
            loadedAFMByDatasetID = datasets
        }
    }
}
