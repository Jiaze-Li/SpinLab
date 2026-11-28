import Foundation

// MARK: - Formal Live Plot assets (Task 6 design §2.6-D)
//
// A Plot is a derived asset with files (`storage/<plt>/rev_N`). Publishing and updating follow the
// ingest/revise template: operation record first, files staged and verified, then one SQLite
// transaction that re-checks every captured fact and flips the Plot to ready. All of it runs inside
// the same `commitLock` critical section as Dataset revisions, Trash moves and deletions.

/// One Dataset+channel a Plot reads, with the Dataset revision the candidate was computed from.
struct PlotInputRef: Codable, Equatable, Hashable, Sendable {
    let datasetID: String
    let channelID: String
    let revision: Int
}

/// Identity of an input as stored on the Plot (`signal_locator` carries the channel).
/// A nil channel means the locator is missing/undecodable: the Plot is corrupt and is never matched.
struct PlotInputKey: Codable, Equatable, Hashable, Sendable {
    let datasetID: String
    let channelID: String?
}

enum PlotUpdateMode: String, Codable, Sendable {
    /// Dataset set and channels unchanged; only content/revisions move.
    case sameSet
    /// The user chose a Plot built from other data: dependency rows switch atomically.
    case manualSwap
}

struct PlotCommitResult: Codable, Equatable, Sendable {
    let plotID: String
    let revision: Int
}

/// Registered Plot with its inputs and derived Samples; no file content.
struct PlotAssetRow: Equatable, Sendable {
    let record: AssetRecord
    let inputs: [PlotInputKey]
    let sampleUIDs: [String]
    var id: String { record.id }
    var isCorrupt: Bool { inputs.isEmpty || inputs.contains { $0.channelID == nil } }
}

extension LibraryAssetService {
    static let supportedPlotFormats: Set<String> = ["afm_plot_v1"]

    struct PlotOpPayload: Codable {
        var kind: String                      // "publish" | "update"
        var plotID: String
        var format: String
        var requestHash: String
        var expectedPlotRevision: Int?
        var nextRevision: Int
        var stagingRelPath: String
        var targetRelPath: String
        var oldRelPath: String
        var files: [AssetFileEntry]
        var oldFiles: [AssetFileEntry]
        var inputs: [PlotInputRef]
        var expectedUpstream: [PlotInputKey]
        var mode: String?
        var cleanupPending: Bool
        var result: PlotCommitResult?
    }

    // MARK: Publish (new Plot)

    func publishPlot(
        content: StandardizedDatasetContent,
        inputs: [PlotInputRef],
        operationID: String,
        capturedRootURL: URL,
        rootURL: URL
    ) throws -> PlotCommitResult {
        try publishPlotCore(
            content: content, inputs: inputs, operationID: operationID, capturedRootURL: capturedRootURL,
            rootURL: rootURL, onExistingCommit: .verifyRequest, commitGuard: nil
        ).result
    }

    /// How an already committed `plot_publish` row with the same operation ID is treated.
    enum ExistingCommitPolicy {
        /// Manual saves: the retry must be the identical request, otherwise `operationRequestMismatch`.
        case verifyRequest
        /// Automatic intents: the committed row is the receipt; return it without comparing content
        /// (a re-render has a different `savedAt`) and without touching staging or the row.
        case returnReceipt
    }

    func publishPlotCore(
        content: StandardizedDatasetContent,
        inputs: [PlotInputRef],
        operationID: String,
        capturedRootURL: URL,
        rootURL: URL,
        onExistingCommit: ExistingCommitPolicy,
        commitGuard: (() throws -> Void)?
    ) throws -> (result: PlotCommitResult, alreadyCommitted: Bool) {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        try validateFileNames(content.files)
        try validateOperationID(operationID)
        try validatePlotRequest(format: content.format, inputs: inputs)

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(inputs.first?.datasetID ?? "")
        }
        _ = try recoverPending(db: db, rootURL: rootURL)

        let entries = content.files.map(AssetFileEntry.make)
        let hash = plotRequestHash(
            kind: "publish", plotID: nil, expectedRevision: nil, expectedUpstream: [], inputs: inputs,
            mode: nil, entries: entries, format: content.format, root: capturedRootURL
        )
        if let existing = try operation(db, id: operationID) {
            guard existing.type == "plot_publish" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            if existing.state == "committed" {
                let done = try decodeJSON(PlotOpPayload.self, existing.payload)
                if onExistingCommit == .verifyRequest {
                    guard done.requestHash == hash else { throw LibraryAssetError.operationRequestMismatch(operationID) }
                }
                if let result = done.result { return (result, true) }
            }
        }
        // Fast-fail only; the authoritative check runs inside transaction 2 below.
        try commitGuard?()

        let plotID = "plt_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let relPath = "storage/\(plotID)/rev_1"
        var payload = PlotOpPayload(
            kind: "publish", plotID: plotID, format: content.format, requestHash: hash, expectedPlotRevision: nil,
            nextRevision: 1, stagingRelPath: relPath, targetRelPath: relPath, oldRelPath: "", files: entries,
            oldFiles: [], inputs: inputs, expectedUpstream: [], mode: nil, cleanupPending: false, result: nil
        )
        let byteSize = entries.reduce(Int64(0)) { $0 + Int64($1.size) }

        // Transaction 1: validate everything, persist intent and the invisible staging row.
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try requirePlotWriteContext(captured: capturedRootURL, rootURL: rootURL)
            try validatePlotInputs(db, inputs: inputs, rootURL: rootURL)
            let now = Self.timestamp()
            try insertAsset(
                db, id: plotID, kind: "plot", format: content.format, status: "staging", relPath: relPath, revision: 1,
                sha256: AssetHashing.digest(of: entries), byteSize: byteSize, originalFilename: nil,
                liveState: nil, files: entries, now: now
            )
            try insertOperation(db, id: operationID, type: "plot_publish", state: "pending", payload: try encodeJSON(payload))
        }

        do {
            try writeFiles(content.files, toRelativeDirectory: relPath, rootURL: rootURL)
            try verifyFiles(entries, relativeDirectory: relPath, rootURL: rootURL)
        } catch {
            try? abortPlotPublish(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
            throw error
        }
        // A thrown fault point behaves like a crash: no cleanup here, recovery handles it on next use.
        try fault(.plotAfterStaging)
        try fault(.plotBeforeCommit)

        // Transaction 2: re-check captured facts at the commit point. A failed re-check rolls the
        // publish back (files and staging row); the Plot never becomes visible.
        do {
            try db.transaction {
                try requirePlotWriteContext(captured: capturedRootURL, rootURL: rootURL)
                try validatePlotInputs(db, inputs: inputs, rootURL: rootURL)
                try commitGuard?()
                let now = Self.timestamp()
                let changed = try db.execute(
                    "UPDATE assets SET status = 'ready', live_state = 'current', updated_at = ? WHERE asset_id = ? AND status = 'staging';",
                    [.text(now), .text(plotID)]
                )
                guard changed == 1 else { throw LibraryAssetError.assetNotReady(plotID) }
                for input in inputs.sorted(by: { $0.datasetID < $1.datasetID }) {
                    try db.execute(
                        "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'live_input', ?);",
                        [.text(plotID), .text(input.datasetID), .text(try encodeJSON([input.channelID]))]
                    )
                }
                payload.result = PlotCommitResult(plotID: plotID, revision: 1)
                try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(payload))
            }
        } catch {
            try? abortPlotPublish(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
            throw error
        }
        try fault(.plotAfterCommit)
        return (payload.result!, false)
    }

    // MARK: Update (replace an existing Plot; no history kept)

    func updatePlot(
        plotID: String,
        expectedPlotRevision: Int,
        expectedUpstream: [PlotInputKey],
        newInputs: [PlotInputRef],
        mode: PlotUpdateMode,
        content: StandardizedDatasetContent,
        operationID: String,
        capturedRootURL: URL,
        rootURL: URL
    ) throws -> PlotCommitResult {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        try validateFileNames(content.files)
        try validateOperationID(operationID)
        try validatePlotRequest(format: content.format, inputs: newInputs)

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(plotID)
        }
        _ = try recoverPending(db: db, rootURL: rootURL)

        let entries = content.files.map(AssetFileEntry.make)
        let hash = plotRequestHash(
            kind: "update", plotID: plotID, expectedRevision: expectedPlotRevision,
            expectedUpstream: expectedUpstream, inputs: newInputs, mode: mode, entries: entries,
            format: content.format, root: capturedRootURL
        )
        if let existing = try operation(db, id: operationID) {
            guard existing.type == "plot_update" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            if existing.state == "committed" {
                let done = try decodeJSON(PlotOpPayload.self, existing.payload)
                guard done.requestHash == hash else { throw LibraryAssetError.operationRequestMismatch(operationID) }
                if let result = done.result { return result }
            }
        }

        let next = expectedPlotRevision + 1
        var payload = PlotOpPayload(
            kind: "update", plotID: plotID, format: content.format, requestHash: hash,
            expectedPlotRevision: expectedPlotRevision, nextRevision: next,
            stagingRelPath: "storage/\(plotID)/.staging_\(operationID)",
            targetRelPath: "storage/\(plotID)/rev_\(next)", oldRelPath: "", files: entries, oldFiles: [],
            inputs: newInputs, expectedUpstream: expectedUpstream, mode: mode.rawValue, cleanupPending: false, result: nil
        )

        // Transaction 1: the Plot must still be the one the caller saw; persist the recovery intent.
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try requirePlotWriteContext(captured: capturedRootURL, rootURL: rootURL)
            let record = try requireUpdatablePlot(db, plotID: plotID, format: content.format, expectedRevision: expectedPlotRevision)
            payload.oldRelPath = record.storageRelPath
            payload.oldFiles = record.files
            try requireUpstream(db, plotID: plotID, equals: expectedUpstream)
            try validateUpdateInputs(newInputs: newInputs, expected: expectedUpstream, mode: mode)
            try validatePlotInputs(db, inputs: newInputs, rootURL: rootURL)
            try insertOperation(db, id: operationID, type: "plot_update", state: "pending", payload: try encodeJSON(payload))
        }

        let stagingURL: URL
        let targetURL: URL
        do {
            try writeFiles(content.files, toRelativeDirectory: payload.stagingRelPath, rootURL: rootURL)
            try verifyFiles(entries, relativeDirectory: payload.stagingRelPath, rootURL: rootURL)
            stagingURL = try storageURL(rootURL: rootURL, relativePath: payload.stagingRelPath)
            targetURL = try storageURL(rootURL: rootURL, relativePath: payload.targetRelPath)
        } catch {
            try? abortPlotUpdate(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
            throw error
        }
        try fault(.plotAfterStaging)

        // Re-check, then publish the staged directory. The old revision stays readable until commit.
        do {
            try requirePlotWriteContext(captured: capturedRootURL, rootURL: rootURL)
            _ = try requireUpdatablePlot(db, plotID: plotID, format: content.format, expectedRevision: expectedPlotRevision)
            try requireUpstream(db, plotID: plotID, equals: expectedUpstream)
            try validatePlotInputs(db, inputs: newInputs, rootURL: rootURL)
            guard !fileManager.fileExists(atPath: targetURL.path) else {
                throw LibraryAssetError.cleanupFailed("revision directory '\(payload.targetRelPath)' already exists")
            }
            try fileManager.moveItem(at: stagingURL, to: targetURL)
            try syncDirectory(targetURL.deletingLastPathComponent())
        } catch {
            try? abortPlotUpdate(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
            throw error
        }
        try fault(.plotBeforeCommit)

        let byteSize = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
        do {
            try db.transaction {
                try requirePlotWriteContext(captured: capturedRootURL, rootURL: rootURL)
                _ = try requireUpdatablePlot(db, plotID: plotID, format: content.format, expectedRevision: expectedPlotRevision)
                try requireUpstream(db, plotID: plotID, equals: expectedUpstream)
                try validatePlotInputs(db, inputs: newInputs, rootURL: rootURL)
                let now = Self.timestamp()
                if mode == .manualSwap {
                    try applyInputSwap(db, plotID: plotID, newInputs: newInputs)
                }
                try db.execute(
                    """
                    UPDATE assets SET current_revision = ?, storage_rel_path = ?, sha256 = ?, byte_size = ?, files_json = ?,
                                      live_state = 'current', updated_at = ?
                    WHERE asset_id = ?;
                    """,
                    [
                        .int(Int64(next)), .text(payload.targetRelPath), .text(AssetHashing.digest(of: entries)),
                        .int(byteSize), .text(AssetFileEntry.encodeList(entries)), .text(now), .text(plotID)
                    ]
                )
                payload.result = PlotCommitResult(plotID: plotID, revision: next)
                payload.cleanupPending = true
                try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(payload))
            }
        } catch {
            try? abortPlotUpdate(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
            throw error
        }
        try fault(.plotAfterCommit)
        try finishPlotCleanup(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
        return payload.result!
    }

    // MARK: Recovery

    func abortPlotPublish(db: LibraryAssetDatabase, operationID: String, payload: PlotOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        try removeRegisteredFiles(
            rootURL: rootURL, relativeDirectory: payload.targetRelPath, names: payload.files.map(\.name),
            removeWriterTemps: true, emptyDirectoryCandidates: [payload.targetRelPath, "storage/\(payload.plotID)"], report: &report
        )
        try db.transaction {
            try db.execute("DELETE FROM assets WHERE asset_id = ? AND status = 'staging';", [.text(payload.plotID)])
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }

    /// Rolls back an unfinished update. The target `rev_N` is removed only while the Plot still sits at the
    /// expected revision; otherwise that directory belongs to another, committed update.
    func abortPlotUpdate(db: LibraryAssetDatabase, operationID: String, payload: PlotOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        let names = payload.files.map(\.name)
        try removeRegisteredFiles(
            rootURL: rootURL, relativeDirectory: payload.stagingRelPath, names: names,
            removeWriterTemps: true, emptyDirectoryCandidates: [payload.stagingRelPath], report: &report
        )
        if try currentRevision(db, datasetID: payload.plotID) == payload.expectedPlotRevision {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: payload.targetRelPath, names: names,
                removeWriterTemps: true, emptyDirectoryCandidates: [payload.targetRelPath], report: &report
            )
        }
        try db.transaction {
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }

    func finishPlotCleanup(db: LibraryAssetDatabase, operationID: String, payload: PlotOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        if !payload.oldRelPath.isEmpty, payload.oldRelPath != payload.targetRelPath {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: payload.oldRelPath, names: payload.oldFiles.map(\.name),
                removeWriterTemps: false, emptyDirectoryCandidates: [payload.oldRelPath], report: &report
            )
        }
        var done = payload
        done.cleanupPending = false
        try db.transaction {
            try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(done))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }

    // MARK: Reading

    /// Every ready Plot with its inputs and derived Samples (no file content).
    func listPlots(rootURL: URL) throws -> [PlotAssetRow] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        let formats = Self.supportedPlotFormats.sorted()
        let marks = formats.map { _ in "?" }.joined(separator: ",")
        let plots = try db.query(
            "SELECT * FROM assets WHERE kind = 'plot' AND status = 'ready' AND format IN (\(marks)) ORDER BY updated_at DESC, asset_id;",
            formats.map { .text($0) }
        ).map(AssetRecord.init(row:))
        return try plots.map { record in
            PlotAssetRow(
                record: record, inputs: try plotInputs(db, plotID: record.id),
                sampleUIDs: try plotSampleUIDs(db, plotID: record.id)
            )
        }
    }

    /// Reads and verifies a single registered file of a ready Plot (e.g. its manifest or thumbnail PNG).
    func readPlotFile(plotID: String, name: String, rootURL: URL) throws -> Data {
        try requireV2(rootURL)
        try validateFileName(name)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager),
              let record = try assetRecord(db, id: plotID), record.kind == "plot" else {
            throw LibraryAssetError.assetNotFound(plotID)
        }
        guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(plotID) }
        guard let entry = record.files.first(where: { $0.name == name }) else {
            throw LibraryAssetError.datasetCorrupt("plot '\(plotID)' has no file '\(name)'")
        }
        let url = try storageURL(rootURL: rootURL, relativePath: record.storageRelPath + "/" + name)
        guard let data = try? Data(contentsOf: url), data.count == entry.size, AssetHashing.sha256Hex(data) == entry.sha256 else {
            throw LibraryAssetError.datasetCorrupt("plot file '\(name)' is missing or failed verification")
        }
        return data
    }

    /// Reads every file of a ready Plot (hash-verified) in one critical section, with its registration facts.
    func loadPlot(plotID: String, rootURL: URL) throws -> (row: PlotAssetRow, files: [String: Data]) {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager),
              let record = try assetRecord(db, id: plotID), record.kind == "plot" else {
            throw LibraryAssetError.assetNotFound(plotID)
        }
        guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(plotID) }
        try verifyFiles(record.files, relativeDirectory: record.storageRelPath, rootURL: rootURL)
        var files: [String: Data] = [:]
        for entry in record.files {
            files[entry.name] = try Data(contentsOf: try storageURL(rootURL: rootURL, relativePath: record.storageRelPath + "/" + entry.name))
        }
        let row = PlotAssetRow(
            record: record, inputs: try plotInputs(db, plotID: plotID), sampleUIDs: try plotSampleUIDs(db, plotID: plotID)
        )
        return (row, files)
    }

    // MARK: - Internals

    func plotInputs(_ db: LibraryAssetDatabase, plotID: String) throws -> [PlotInputKey] {
        try db.query(
            "SELECT upstream_asset_id, signal_locator FROM asset_dependencies WHERE consumer_asset_id = ? AND dependency_kind = 'live_input' ORDER BY upstream_asset_id;",
            [.text(plotID)]
        ).compactMap { row in
            guard let id = row.string("upstream_asset_id") else { return nil }
            let channels: [String]? = row.string("signal_locator").flatMap {
                try? JSONDecoder().decode([String].self, from: Data($0.utf8))
            }
            return PlotInputKey(datasetID: id, channelID: (channels?.count == 1) ? channels?.first : nil)
        }
    }

    private func plotSampleUIDs(_ db: LibraryAssetDatabase, plotID: String) throws -> [String] {
        try db.query(
            """
            SELECT DISTINCT l.sample_uid FROM asset_dependencies d_plot
            JOIN asset_dependencies d_src ON d_src.consumer_asset_id = d_plot.upstream_asset_id AND d_src.dependency_kind = 'dataset_source'
            JOIN sample_asset_links l ON l.asset_id = d_src.upstream_asset_id
            WHERE d_plot.consumer_asset_id = ? AND d_plot.dependency_kind = 'live_input' AND l.ownership_status = 'active'
            ORDER BY l.sample_uid;
            """,
            [.text(plotID)]
        ).compactMap { $0.string("sample_uid") }
    }

    func validatePlotRequest(format: String, inputs: [PlotInputRef]) throws {
        guard Self.supportedPlotFormats.contains(format) else {
            throw LibraryAssetError.invalidPayload("unsupported plot format '\(format)'")
        }
        guard !inputs.isEmpty, Set(inputs.map(\.datasetID)).count == inputs.count, inputs.allSatisfy({ !$0.channelID.isEmpty }) else {
            throw LibraryAssetError.invalidPayload("a plot needs at least one distinct dataset input with a channel")
        }
    }

    private func validateUpdateInputs(newInputs: [PlotInputRef], expected: [PlotInputKey], mode: PlotUpdateMode) throws {
        if mode == .sameSet {
            let newKeys = Set(newInputs.map { PlotInputKey(datasetID: $0.datasetID, channelID: $0.channelID) })
            guard newKeys == Set(expected) else {
                throw LibraryAssetError.invalidPayload("a same-set update must keep the dataset set and channels")
            }
        }
    }

    /// Captured Library must be the current one and this process must actually hold its write lease.
    func requirePlotWriteContext(captured: URL, rootURL: URL) throws {
        guard LibraryWriteLease.canonicalPath(of: captured) == LibraryWriteLease.canonicalPath(of: rootURL) else {
            throw LibraryAssetError.libraryContextChanged("a different Library is now open")
        }
        guard writeLease.holdsWritableLease(for: rootURL) else {
            throw LibraryAssetError.libraryContextChanged("this SpinLab does not hold the write lease for the Library")
        }
    }

    private func requireUpdatablePlot(
        _ db: LibraryAssetDatabase, plotID: String, format: String, expectedRevision: Int
    ) throws -> AssetRecord {
        guard let record = try assetRecord(db, id: plotID), record.kind == "plot" else {
            throw LibraryAssetError.assetNotFound(plotID)
        }
        guard record.status == "ready", record.format == format else { throw LibraryAssetError.assetNotReady(plotID) }
        guard record.currentRevision == expectedRevision else {
            throw LibraryAssetError.plotRevisionMismatch(plotID: plotID, expected: expectedRevision, current: record.currentRevision)
        }
        return record
    }

    private func requireUpstream(_ db: LibraryAssetDatabase, plotID: String, equals expected: [PlotInputKey]) throws {
        guard Set(try plotInputs(db, plotID: plotID)) == Set(expected) else {
            throw LibraryAssetError.plotInputsChanged(plotID)
        }
    }

    /// Every input must be a ready Dataset still at the captured revision, offer the channel, and belong to
    /// a Source with active ownership by a Sample that is not in the Trash.
    func validatePlotInputs(_ db: LibraryAssetDatabase, inputs: [PlotInputRef], rootURL: URL) throws {
        for input in inputs {
            guard let record = try assetRecord(db, id: input.datasetID), record.kind == "dataset" else {
                throw LibraryAssetError.assetNotFound(input.datasetID)
            }
            guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(input.datasetID) }
            guard record.currentRevision == input.revision else {
                throw LibraryAssetError.staleRevision(datasetID: input.datasetID, expected: input.revision, current: record.currentRevision)
            }
            guard let link = try db.query(
                "SELECT upstream_asset_id, signal_locator FROM asset_dependencies WHERE consumer_asset_id = ? AND dependency_kind = 'dataset_source';",
                [.text(input.datasetID)]
            ).first, let sourceID = link.string("upstream_asset_id") else {
                throw LibraryAssetError.ownershipViolation("dataset '\(input.datasetID)' has no source relation")
            }
            let channels = link.string("signal_locator").flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
            guard channels.contains(input.channelID) else {
                throw LibraryAssetError.invalidPayload("dataset '\(input.datasetID)' has no channel '\(input.channelID)'")
            }
            guard let owner = try sourceOwnership(db, sourceID: sourceID), !owner.isHistorical else {
                throw LibraryAssetError.ownershipViolation("dataset '\(input.datasetID)' has no active sample ownership")
            }
            guard activeSample(owner.sampleUID, rootURL: rootURL) != nil else {
                throw LibraryAssetError.ownershipViolation("the owning sample of '\(input.datasetID)' is in the Trash or unreadable")
            }
        }
    }

    /// Replaces the Plot's `live_input` rows in the caller's transaction: delete removed, update channel
    /// where the Dataset stays, insert new. No intermediate state is ever visible.
    private func applyInputSwap(_ db: LibraryAssetDatabase, plotID: String, newInputs: [PlotInputRef]) throws {
        let current = Set(try plotInputs(db, plotID: plotID).map(\.datasetID))
        let wanted = Dictionary(uniqueKeysWithValues: newInputs.map { ($0.datasetID, $0.channelID) })
        for removed in current.subtracting(wanted.keys) {
            try db.execute(
                "DELETE FROM asset_dependencies WHERE consumer_asset_id = ? AND upstream_asset_id = ? AND dependency_kind = 'live_input';",
                [.text(plotID), .text(removed)]
            )
        }
        for (datasetID, channelID) in wanted.sorted(by: { $0.key < $1.key }) {
            let locator = SQLValue.text(try encodeJSON([channelID]))
            if current.contains(datasetID) {
                try db.execute(
                    "UPDATE asset_dependencies SET signal_locator = ? WHERE consumer_asset_id = ? AND upstream_asset_id = ? AND dependency_kind = 'live_input';",
                    [locator, .text(plotID), .text(datasetID)]
                )
            } else {
                try db.execute(
                    "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'live_input', ?);",
                    [.text(plotID), .text(datasetID), locator]
                )
            }
        }
    }

    func plotRequestHash(
        kind: String, plotID: String?, expectedRevision: Int?, expectedUpstream: [PlotInputKey],
        inputs: [PlotInputRef], mode: PlotUpdateMode?, entries: [AssetFileEntry], format: String, root: URL
    ) -> String {
        var lines = [
            "kind=\(kind)", "plot=\(plotID ?? "-")", "rev=\(expectedRevision.map(String.init) ?? "-")", "format=\(format)",
            "mode=\(mode?.rawValue ?? "-")", "root=\(LibraryWriteLease.canonicalPath(of: root))",
            "files=\(AssetHashing.digest(of: entries))",
        ]
        lines += expectedUpstream.map { "exp=\($0.datasetID)|\($0.channelID ?? "-")" }.sorted()
        lines += inputs.map { "in=\($0.datasetID)|\($0.channelID)|\($0.revision)" }.sorted()
        return AssetHashing.sha256Hex(Data(lines.joined(separator: "\n").utf8))
    }
}
