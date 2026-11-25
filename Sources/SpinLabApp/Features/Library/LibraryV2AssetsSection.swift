import SwiftUI

struct LibraryV2AssetsSection: View {
    @Environment(SpinLabAppState.self) private var appState
    let sample: LibrarySample

    @State private var sourceGroups: [SampleSourceGroup] = []
    @State private var loadError: String?
    @State private var loadedAFMByDatasetID: [String: Result<LoadedDataset<CanonicalAFMDataset>, Error>] = [:]
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text("Standard Assets (V2)")
                    .font(AppFontScale.sectionTitle)
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

            if loadError == nil && sourceGroups.isEmpty {
                Text("No V2 sources owned by this sample.")
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
    }

    @ViewBuilder
    private func sourceGroupCard(_ group: SampleSourceGroup) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    Text("SOURCE • \(group.source.id)")
                        .font(AppFontScale.groupHeader)
                    Spacer()
                    Text(group.source.format)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let filename = group.source.originalFilename, !filename.isEmpty {
                    Text("Original file: \(filename)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if group.datasets.isEmpty {
                    Text("No standardized datasets registered for this source.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(group.datasets, id: \.id) { dataset in
                        datasetCard(dataset)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func datasetCard(_ dataset: AssetRecord) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Divider()
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                Text("DATASET • \(dataset.id)")
                    .font(AppFontScale.groupHeader)
                Text("rev \(dataset.currentRevision)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if dataset.format == AFMDatasetCodec.format {
                datasetDetails(for: dataset.id)
            } else {
                Text("Format: \(dataset.format)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func datasetDetails(for datasetID: String) -> some View {
        switch loadedAFMByDatasetID[datasetID] {
        case .none:
            EmptyView()
        case let .some(.failure(error)):
            Text("Dataset read error: \(error.localizedDescription)")
                .font(.callout)
                .foregroundStyle(.red)
        case let .some(.success(loaded)):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Source status: \(sourceAvailabilityLabel(loaded.sourceAvailability))")
                    .font(.callout)
                    .foregroundStyle(loaded.sourceAvailability == .available ? Color.secondary : Color.orange)

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
