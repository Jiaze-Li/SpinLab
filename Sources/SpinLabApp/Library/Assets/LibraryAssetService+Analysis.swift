import Foundation

/// A standard Dataset read for analysis, captured at one point under `commitLock` together with
/// the identity and ownership facts later commits must re-check (Task 6 design §2.6-B).
struct AnalysisDatasetContext<Dataset> {
    let datasetID: String
    let revision: Int
    let sourceID: String
    /// The active owner Sample. Ownership is derived Dataset → Source → Sample, never from paths.
    let sampleUID: String
    let isSampleTrashed: Bool
    let originalFileName: String
    /// Stable channel IDs recorded on the `dataset_source` dependency (`signal_locator`).
    let channelIDs: [String]
    let dataset: Dataset
    /// Independent of dataset readability (Task 5): a missing Source payload does not block analysis.
    let sourceAvailability: SourceAvailability
}

extension AnalysisDatasetContext: Sendable where Dataset: Sendable {}

/// One selectable standard Dataset, listed without decoding any matrix.
struct AnalysisDatasetSummary: Equatable, Sendable {
    let datasetID: String
    let revision: Int
    let sourceID: String
    let sampleUID: String
    let originalFileName: String
    let channelIDs: [String]
    /// Display facts of the owning Sample, read once per Sample; never used as identity.
    let sampleDisplayName: String
    let batchID: String
    let substrate: String
}

extension LibraryAssetService {

    /// Reads one Dataset plus its source/ownership facts in a single `commitLock` critical section.
    /// A missing `dataset_source` or missing/historical ownership is `ownershipViolation`; this is
    /// distinct from a missing Source payload, which is only reported through `sourceAvailability`.
    func loadDatasetForAnalysis<Codec: DatasetPayloadCodec>(
        datasetID: String, codec: Codec, rootURL: URL
    ) throws -> AnalysisDatasetContext<Codec.Dataset> {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        let loaded = try loadDataset(datasetID: datasetID, codec: codec, rootURL: rootURL)
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(datasetID)
        }
        guard let link = try db.query(
            "SELECT upstream_asset_id, signal_locator FROM asset_dependencies WHERE consumer_asset_id = ? AND dependency_kind = 'dataset_source';",
            [.text(datasetID)]
        ).first, let sourceID = link.string("upstream_asset_id") else {
            throw LibraryAssetError.ownershipViolation("dataset '\(datasetID)' has no source relation")
        }
        guard let owner = try sourceOwnership(db, sourceID: sourceID), !owner.isHistorical else {
            throw LibraryAssetError.ownershipViolation("dataset '\(datasetID)' has no active sample ownership")
        }
        guard let source = try assetRecord(db, id: sourceID) else {
            throw LibraryAssetError.ownershipViolation("source '\(sourceID)' of dataset '\(datasetID)' is missing")
        }
        return AnalysisDatasetContext(
            datasetID: datasetID, revision: loaded.revision, sourceID: sourceID, sampleUID: owner.sampleUID,
            isSampleTrashed: activeSample(owner.sampleUID, rootURL: rootURL) == nil,
            originalFileName: source.originalFilename ?? "",
            channelIDs: decodeChannelIDs(link.string("signal_locator")),
            dataset: loaded.dataset, sourceAvailability: loaded.sourceAvailability
        )
    }

    /// One batched query for the Workbench list: ready Datasets of `format` whose Source has an
    /// active Sample owner that is not in the Trash. No matrix is decoded and no per-Sample
    /// integrity scan runs.
    func listAnalysisDatasets(format: String, rootURL: URL) throws -> [AnalysisDatasetSummary] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        let rows = try db.query(
            """
            SELECT d.asset_id AS dataset_id, d.current_revision AS revision, s.asset_id AS source_id,
                   s.original_filename AS file_name, l.sample_uid AS sample_uid, dep.signal_locator AS locator
            FROM assets d
            JOIN asset_dependencies dep ON dep.consumer_asset_id = d.asset_id AND dep.dependency_kind = 'dataset_source'
            JOIN assets s ON s.asset_id = dep.upstream_asset_id AND s.kind = 'source' AND s.status = 'ready'
            JOIN sample_asset_links l ON l.asset_id = s.asset_id AND l.ownership_status = 'active'
            WHERE d.kind = 'dataset' AND d.status = 'ready' AND d.format = ?
            ORDER BY s.created_at, d.asset_id;
            """,
            [.text(format)]
        )
        var sampleCache: [String: LibrarySample?] = [:]
        var result: [AnalysisDatasetSummary] = []
        for row in rows {
            guard let datasetID = row.string("dataset_id"), let sourceID = row.string("source_id"),
                  let uid = row.string("sample_uid") else { continue }
            let sample: LibrarySample?
            if let cached = sampleCache[uid] { sample = cached } else {
                sample = activeSample(uid, rootURL: rootURL)
                sampleCache[uid] = sample
            }
            guard let sample else { continue }
            result.append(AnalysisDatasetSummary(
                datasetID: datasetID, revision: Int(row.int("revision") ?? 1), sourceID: sourceID, sampleUID: uid,
                originalFileName: row.string("file_name") ?? "", channelIDs: decodeChannelIDs(row.string("locator")),
                sampleDisplayName: sample.displayName, batchID: sample.batchId, substrate: sample.substrateDisplay
            ))
        }
        return result
    }

    /// nil for a missing/unreadable/trashed Sample: it must not be offered or committed against.
    func activeSample(_ uid: String, rootURL: URL) -> LibrarySample? {
        let url = libraryStore.v2SampleDirectoryURL(rootURL, sampleUID: uid).appending(path: "sample.json")
        guard fileManager.fileExists(atPath: url.path), let sample = libraryStore.decodeSample(from: url),
              !sample.isTrashed else { return nil }
        return sample
    }

    private func decodeChannelIDs(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
}
