import Foundation

// MARK: - Task 7: automatic AFM plotting — durable intent, receipts, commit guard
//
// Storage-layer pieces only. The service owns no analysis: it persists the user's intent with the
// ingest commit, answers "is there already a committed publish for this Dataset revision", withdraws
// a publish at the commit point when the preset/session changed, and lists unfinished intents.
// Everything runs under the same `commitLock` as every other asset commit.

/// Persisted with the ingest commit when automation was enabled: which applied preset the user had.
struct AutoPlotIntent: Codable, Equatable, Hashable, Sendable {
    let presetVersionID: String
}

/// Stable identity of one automatic plot: the Dataset and its revision only. The preset version is
/// *not* part of it (it only decides whether publishing is still allowed), so re-delivery after an
/// Apply hits the same receipt and a manually deleted plot is never redrawn.
enum AutoPlotIdentity {
    static let operationPrefix = "auto-afm-"

    static func operationID(datasetID: String, revision: Int) -> String {
        "\(operationPrefix)\(datasetID)-r\(revision)"
    }
}

enum AutoPlotPublishOutcome: Equatable, Sendable {
    /// This call made the plot visible.
    case published(PlotCommitResult)
    /// A committed publish for this identity already exists. The plot may since have been deleted by
    /// the user, so no plot ID is reported and nothing is recreated.
    case alreadyPublished
}

/// A committed `plot_publish` row for an operation ID. Rows stay after the plot is deleted.
struct PlotPublishReceipt: Equatable, Sendable {
    let operationID: String
    let result: PlotCommitResult
}

struct PendingAutoPlotIntent: Equatable, Sendable {
    let datasetID: String
    let revision: Int
    let sampleUID: String
    let presetVersionID: String
}

/// What an in-process automatic task captured when it started.
struct AutoPlotTaskContext: Equatable, Sendable {
    let rootPath: String
    let sessionID: String
    let presetVersionID: String
}

/// Process-wide, per-Library view of the applied preset used by the commit guard. It is only ever
/// changed while `LibraryAssetService.commitLock` is held and is re-seeded from the preset file
/// whenever the Library is opened anew (new write-lease session).
final class AutoPlotGate: @unchecked Sendable {
    struct Snapshot: Equatable {
        var sessionID: String
        var enabled: Bool
        var presetVersionID: String
    }

    static let shared = AutoPlotGate()
    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]

    func snapshot(rootPath: String) -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshots[rootPath]
    }

    func set(_ snapshot: Snapshot?, rootPath: String) {
        lock.lock(); defer { lock.unlock() }
        snapshots[rootPath] = snapshot
    }
}

extension LibraryAssetService {
    static let autoPlotPresetRelativePath = "_spinlab/afm_auto_plot_preset.json"

    // MARK: Preset file + gate

    func autoPlotPresetURL(rootURL: URL) -> URL {
        rootURL.appending(path: Self.autoPlotPresetRelativePath, directoryHint: .notDirectory)
    }

    func readAutoPlotPresetFile(rootURL: URL) -> AFMAutoPlotPresetLoad {
        let url = autoPlotPresetURL(rootURL: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .unreadable("the preset file cannot be read") }
        guard let preset = try? JSONDecoder().decode(AFMAutoPlotPreset.self, from: data) else {
            return .unreadable("the preset file is damaged")
        }
        guard preset.schemaVersion == AFMAutoPlotPreset.currentSchemaVersion else {
            return .unreadable("the preset file has an unknown version \(preset.schemaVersion)")
        }
        return .loaded(preset)
    }

    /// Must hold `commitLock`. Seeds the gate from one read of the file when this open of the Library
    /// has not been seen yet; returns the load that backs the gate right now.
    private func seedGateIfNeeded(rootURL: URL) -> (load: AFMAutoPlotPresetLoad, sessionID: String) {
        let rootPath = LibraryWriteLease.canonicalPath(of: rootURL)
        let session = writeLease.sessionID ?? "no-session"
        let load = readAutoPlotPresetFile(rootURL: rootURL)
        if AutoPlotGate.shared.snapshot(rootPath: rootPath)?.sessionID != session {
            let effective = load.effective
            AutoPlotGate.shared.set(
                .init(sessionID: session, enabled: effective?.enabled ?? false, presetVersionID: effective?.presetVersionID ?? ""),
                rootPath: rootPath
            )
        }
        return (load, session)
    }

    /// The applied preset as automation sees it now (one atomic read under the commit lock).
    func currentAutoPlotPreset(rootURL: URL) throws -> (load: AFMAutoPlotPresetLoad, sessionID: String) {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        return seedGateIfNeeded(rootURL: rootURL)
    }

    /// Applies new preset content (always a new `presetVersionID`). Gate first, then file; a failed
    /// write restores the gate. Returns the preset as stored.
    @discardableResult
    func applyAutoPlotPreset(_ preset: AFMAutoPlotPreset, rootURL: URL) throws -> AFMAutoPlotPreset {
        try requireV2(rootURL)
        try requireAutoPlotWritable(rootURL)
        guard !preset.enabled || preset.channelRule.isUsable else {
            throw LibraryAssetError.invalidPayload("an enabled preset needs a channel rule")
        }
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        var stored = preset
        stored.schemaVersion = AFMAutoPlotPreset.currentSchemaVersion
        stored.presetVersionID = AFMAutoPlotPreset.newVersionID()
        try replaceAutoPlotPreset(stored, rootURL: rootURL)
        return stored
    }

    /// Switches automation on or off, keeping the applied values. A new version ID is minted.
    @discardableResult
    func setAutoPlotEnabled(_ enabled: Bool, rootURL: URL) throws -> AFMAutoPlotPreset {
        try requireV2(rootURL)
        try requireAutoPlotWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        let (load, _) = seedGateIfNeeded(rootURL: rootURL)
        guard case var .loaded(preset) = load else {
            if case let .unreadable(reason) = load { throw LibraryAssetError.invalidPayload("preset unusable: \(reason)") }
            throw LibraryAssetError.invalidPayload("Apply a preset before switching automation on")
        }
        guard !enabled || preset.channelRule.isUsable else {
            throw LibraryAssetError.invalidPayload("an enabled preset needs a channel rule")
        }
        preset.enabled = enabled
        preset.presetVersionID = AFMAutoPlotPreset.newVersionID()
        try replaceAutoPlotPreset(preset, rootURL: rootURL)
        return preset
    }

    /// Must hold `commitLock`.
    private func replaceAutoPlotPreset(_ preset: AFMAutoPlotPreset, rootURL: URL) throws {
        _ = seedGateIfNeeded(rootURL: rootURL)
        let rootPath = LibraryWriteLease.canonicalPath(of: rootURL)
        let session = writeLease.sessionID ?? "no-session"
        let previous = AutoPlotGate.shared.snapshot(rootPath: rootPath)
        AutoPlotGate.shared.set(
            .init(sessionID: session, enabled: preset.enabled, presetVersionID: preset.presetVersionID), rootPath: rootPath
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try AtomicFileWriter(fileManager: fileManager).write(
                try encoder.encode(preset), to: autoPlotPresetURL(rootURL: rootURL)
            )
        } catch {
            AutoPlotGate.shared.set(previous, rootPath: rootPath)
            throw error
        }
    }

    /// Context for a task that starts now, or nil when automation is not currently on.
    func beginAutoPlotTask(rootURL: URL) throws -> AutoPlotTaskContext? {
        let (load, session) = try currentAutoPlotPreset(rootURL: rootURL)
        guard let preset = load.effective, preset.enabled else { return nil }
        return AutoPlotTaskContext(
            rootPath: LibraryWriteLease.canonicalPath(of: rootURL), sessionID: session, presetVersionID: preset.presetVersionID
        )
    }

    /// Cheap, IO-free check used both as a fast-fail and inside the commit transaction.
    func autoPlotGuard(_ context: AutoPlotTaskContext) -> () throws -> Void {
        { [writeLease] in
            guard writeLease.sessionID == context.sessionID else {
                throw LibraryAssetError.autoPlotCancelled("the Library was closed or switched")
            }
            guard let snapshot = AutoPlotGate.shared.snapshot(rootPath: context.rootPath),
                  snapshot.sessionID == context.sessionID else {
                throw LibraryAssetError.autoPlotCancelled("the Library session changed")
            }
            guard snapshot.enabled else { throw LibraryAssetError.autoPlotCancelled("automatic plotting was turned off") }
            guard snapshot.presetVersionID == context.presetVersionID else {
                throw LibraryAssetError.autoPlotCancelled("the preset was changed")
            }
        }
    }

    // MARK: Receipt + publish

    /// Read-only: the committed publish for `operationID`, if any. Pending/aborted/other kinds are "none".
    func plotPublishReceipt(operationID: String, rootURL: URL) throws -> PlotPublishReceipt? {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager),
              let row = try operation(db, id: operationID), row.type == "plot_publish", row.state == "committed",
              let result = try decodeJSON(PlotOpPayload.self, row.payload).result else { return nil }
        return PlotPublishReceipt(operationID: operationID, result: result)
    }

    /// New-plot publish for an automatic intent. A committed receipt wins before anything is compared
    /// or staged; otherwise the commit guard runs again inside the commit transaction.
    func publishAutoPlot(
        content: StandardizedDatasetContent,
        input: PlotInputRef,
        capturedRootURL: URL,
        rootURL: URL,
        context: AutoPlotTaskContext
    ) throws -> AutoPlotPublishOutcome {
        let operationID = AutoPlotIdentity.operationID(datasetID: input.datasetID, revision: input.revision)
        let outcome = try publishPlotCore(
            content: content, inputs: [input], operationID: operationID, capturedRootURL: capturedRootURL,
            rootURL: rootURL, onExistingCommit: .returnReceipt, commitGuard: autoPlotGuard(context)
        )
        return outcome.alreadyCommitted ? .alreadyPublished : .published(outcome.result)
    }

    // MARK: Recovery query

    /// Unfinished intents for the applied preset version. The authority is the coordinator's follow-up
    /// row bound to one specific *standardize operation*: only a committed, successful receipt of that
    /// operation counts, its Datasets must still be ready at the receipted revision with an active
    /// Source owner, and no committed publish receipt may exist. A refused standardization closes the
    /// follow-up; an uncommitted one stays pending for the retry. The Source's latest outcome is never
    /// consulted, so another standardization round cannot be mistaken for this intent.
    func pendingAutoPlotIntents(presetVersionID: String, format: String, rootURL: URL) throws -> [PendingAutoPlotIntent] {
        try requireV2(rootURL)
        if (try? requireWritable(rootURL)) != nil { try? settleFollowups(rootURL: rootURL) }
        let rows: [SQLRow]
        do {
            Self.commitLock.lock()
            defer { Self.commitLock.unlock() }
            guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
                return []
            }
            rows = try db.query(
                """
                SELECT d.asset_id AS dataset_id, d.current_revision AS revision, l.sample_uid AS sample_uid
                FROM coordinator_followup f
                CROSS JOIN asset_operations o ON o.operation_id = f.standardize_operation_id
                    AND o.op_type = 'standardize' AND o.state = 'committed'
                CROSS JOIN json_each(o.payload_json, '$.result.standardized.datasetIDs') j
                CROSS JOIN assets d ON d.asset_id = j.value AND d.kind = 'dataset' AND d.status = 'ready' AND d.format = ?
                CROSS JOIN asset_dependencies dep ON dep.consumer_asset_id = d.asset_id AND dep.dependency_kind = 'dataset_source'
                CROSS JOIN sample_asset_links l ON l.asset_id = dep.upstream_asset_id AND l.ownership_status = 'active'
                WHERE f.kind = 'auto_plot' AND f.state = 'pending'
                  AND json_extract(f.request_json, '$.presetVersionID') = ?
                  AND d.current_revision = json_extract(o.payload_json, '$.result.standardized.datasetRevision')
                  AND NOT EXISTS (
                      SELECT 1 FROM asset_operations r
                      WHERE r.op_type = 'plot_publish' AND r.state = 'committed'
                        AND r.operation_id = ? || d.asset_id || '-r' || d.current_revision
                  )
                ORDER BY o.created_at, d.asset_id;
                """,
                [.text(format), .text(presetVersionID), .text(AutoPlotIdentity.operationPrefix)]
            )
        }
        var active: [String: Bool] = [:]
        var pending: [PendingAutoPlotIntent] = []
        for row in rows {
            guard let datasetID = row.string("dataset_id"), let uid = row.string("sample_uid") else { continue }
            let isActive: Bool
            if let cached = active[uid] { isActive = cached } else {
                isActive = activeSample(uid, rootURL: rootURL) != nil
                active[uid] = isActive
            }
            guard isActive else { continue }
            pending.append(PendingAutoPlotIntent(
                datasetID: datasetID, revision: Int(row.int("revision") ?? 1), sampleUID: uid, presetVersionID: presetVersionID
            ))
        }
        return pending
    }
}

extension LibraryAssetService {
    /// Task context and the exact preset it belongs to, from one read under the commit lock. Nil when
    /// automation is off (or the preset is unreadable). The preset's version always equals the context's.
    func beginAutoPlotRun(rootURL: URL) throws -> (context: AutoPlotTaskContext, preset: AFMAutoPlotPreset)? {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let context = try beginAutoPlotTask(rootURL: rootURL),
              let preset = readAutoPlotPresetFile(rootURL: rootURL).effective,
              preset.presetVersionID == context.presetVersionID else { return nil }
        return (context, preset)
    }
}

extension LibraryAssetService {
    /// Preset writes need this instance to hold the write lease, not only to avoid a read-only mark.
    func requireAutoPlotWritable(_ rootURL: URL) throws {
        try requireWritable(rootURL)
        guard writeLease.holdsWritableLease(for: rootURL) else {
            throw LibraryAssetError.libraryContextChanged("this SpinLab does not hold the write lease for the Library")
        }
    }
}
