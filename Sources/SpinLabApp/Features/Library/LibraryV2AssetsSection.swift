import SwiftUI

struct LibraryV2AssetsSection: View {
    @Environment(SpinLabAppState.self) private var appState
    let sample: LibrarySample

    @State private var assets: [AssetRecord] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var linkedUIDsByAssetID: [String: [String]] = [:]
    @State private var loadedAFMByDatasetID: [String: Result<LoadedDataset<CanonicalAFMDataset>, Error>] = [:]
    @State private var reloadToken = 0

    private var currentSampleUID: String {
        sample.sampleUID ?? sample.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text("Shared Assets (V2)")
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
            } else if let actionError {
                Text(actionError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if loadError == nil && assets.isEmpty {
                Text("No V2 assets linked to this sample.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets, id: \.id) { asset in
                    assetRow(asset)
                }
            }
        }
        .onAppear { reloadAssets() }
        .onChange(of: sample.id) { _, _ in reloadAssets() }
        .onChange(of: reloadToken) { _, _ in reloadAssets() }
    }

    @ViewBuilder
    private func assetRow(_ asset: AssetRecord) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    Text("\(asset.kind.uppercased()) • \(asset.id)")
                        .font(AppFontScale.groupHeader)
                    if asset.kind == "dataset" {
                        Text("rev \(asset.currentRevision)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    shareMenu(for: asset)
                    Button("Unlink") {
                        unlink(asset)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let filename = asset.originalFilename, !filename.isEmpty {
                    Text("Original file: \(filename)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let linked = linkedUIDsByAssetID[asset.id] {
                    Text("Linked samples (\(linked.count)): \(linked.joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if asset.kind == "dataset", asset.format == AFMDatasetCodec.format {
                    datasetDetails(for: asset.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("• \(channel.displayLabel) [\(channel.canonicalUnit.isEmpty ? "unknown" : channel.canonicalUnit)] (\(rows)×\(cols))")
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private func shareMenu(for asset: AssetRecord) -> some View {
        let alreadyLinked = Set(linkedUIDsByAssetID[asset.id] ?? [])
        let candidates = appState.v2ActiveSamplesByBatch.flatMap(\.samples).filter { candidate in
            let uid = candidate.sampleUID ?? candidate.id
            return !alreadyLinked.contains(uid)
        }
        Menu("Share") {
            if candidates.isEmpty {
                Text("No other active V2 samples")
            } else {
                ForEach(candidates) { candidate in
                    let uid = candidate.sampleUID ?? candidate.id
                    Button("\(candidate.batchId) / \(candidate.displayName) (\(uid))") {
                        link(asset, toSampleUID: uid)
                    }
                }
            }
        }
        .controlSize(.small)
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
        actionError = nil
        switch appState.loadV2Assets(for: sample) {
        case let .failure(error):
            assets = []
            linkedUIDsByAssetID = [:]
            loadedAFMByDatasetID = [:]
            loadError = error.localizedDescription
        case let .success(records):
            assets = records
            var links: [String: [String]] = [:]
            var datasets: [String: Result<LoadedDataset<CanonicalAFMDataset>, Error>] = [:]
            for record in records {
                if case let .success(uids) = appState.loadV2LinkedSampleUIDs(forAssetID: record.id) {
                    links[record.id] = uids
                }
                if record.kind == "dataset", record.format == AFMDatasetCodec.format {
                    datasets[record.id] = appState.loadV2AFMDataset(datasetID: record.id)
                }
            }
            linkedUIDsByAssetID = links
            loadedAFMByDatasetID = datasets
        }
    }

    private func link(_ asset: AssetRecord, toSampleUID uid: String) {
        actionError = nil
        if case let .failure(error) = appState.linkV2Asset(assetID: asset.id, toSampleUID: uid) {
            actionError = error.localizedDescription
        }
        reloadAssets()
    }

    private func unlink(_ asset: AssetRecord) {
        actionError = nil
        if case let .failure(error) = appState.unlinkV2Asset(assetID: asset.id, fromSampleUID: currentSampleUID) {
            actionError = error.localizedDescription
        }
        reloadAssets()
    }
}
