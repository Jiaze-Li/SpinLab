import Foundation

/// Handed to the automatic-plot runner once an ingest has committed. Carries the *persisted* intent,
/// so a replay of an old ingest cannot be turned into a new task by a later preset.
struct AutoPlotTrigger: Equatable, Sendable {
    let datasetIDs: [String]
    let datasetRevision: Int
    let sampleUID: String
    let intent: AutoPlotIntent
    let rootURL: URL
}

/// Stage-by-stage outcome of one V2 target (WP1 §3.2 ④). The three statements stay separate:
/// "the original file is stored" is not "a Dataset exists" is not "it can be analysed".
struct V2TargetApplyResult: Equatable {
    enum Ingest: Equatable {
        case applied(sourceID: String)
        case failed(String)
    }
    enum Standardize: Equatable {
        case standardized
        case notStandardized(code: String)
        /// A technical problem; the Source is safe and only this step is retried.
        case pending(String)
        /// Not reached because the original file was not stored.
        case notReached
    }
    enum Plot: Equatable {
        case none
        case queued
    }

    var sampleUID: String
    var ingest: Ingest
    var standardize: Standardize
    var plot: Plot = .none

    /// Ingest stored and standardization reached a final answer.
    var isFinished: Bool {
        guard case .applied = ingest else { return false }
        switch standardize {
        case .standardized, .notStandardized: return true
        case .pending, .notReached: return false
        }
    }

    var sourceID: String? {
        if case let .applied(id) = ingest { return id }
        return nil
    }

    var problem: String? {
        if case let .failed(message) = ingest { return message }
        if case let .pending(message) = standardize { return message }
        return nil
    }
}

struct InboxArchiveApplyResult: Equatable {
    var copiedTargetCount: Int
    var skippedExistingTargetCount: Int
    var autoPlotTriggers: [AutoPlotTrigger] = []
    /// Per-target stages of a V2 apply (empty for V1).
    var v2TargetResults: [V2TargetApplyResult] = []

    /// V2: some target is not finished. The entry stays in the queue; finished stages are not redone.
    var isIncompleteV2: Bool { !v2TargetResults.isEmpty && !v2TargetResults.allSatisfy(\.isFinished) }
    var incompleteSummary: String {
        v2TargetResults.compactMap { $0.problem.map { "\($0)" } }.joined(separator: " · ")
    }

    var allTargetsSkipped: Bool {
        copiedTargetCount == 0 && skippedExistingTargetCount > 0
    }
}

struct InboxArchiveApplyService {
    private let auditLogger: any AuditLogging
    private let ruleProvider: any SpinLabRuleProviding
    /// Tests inject a service bound to their own write lease or fault hook.
    private let makeAssetService: (LibraryStore) -> LibraryAssetService

    init(
        auditLogger: (any AuditLogging)? = nil, ruleProvider: (any SpinLabRuleProviding)? = nil,
        makeAssetService: ((LibraryStore) -> LibraryAssetService)? = nil
    ) {
        self.auditLogger = auditLogger ?? AuditLogger.shared
        self.ruleProvider = ruleProvider ?? SpinLabRuleProvider.shared
        self.makeAssetService = makeAssetService ?? { LibraryAssetService(libraryStore: $0) }
    }

    enum InboxArchiveApplyError: LocalizedError {
        case sourceFileNotFound
        case drawerNotFound(sampleId: String, candidates: Int)
        case commitFailed(sampleId: String, underlying: AppError)
        /// Destination measurement file and sidecar disagree on whether they
        /// already exist (one present, one missing). Apply refuses to guess
        /// which one is authoritative — no overwrite, no delete, fail closed.
        case destinationArtifactMismatch(sampleId: String, measurementExists: Bool, sidecarExists: Bool)

        var errorDescription: String? {
            switch self {
            case .sourceFileNotFound:
                return "Pending source file does not exist."
            case let .drawerNotFound(sampleId, candidates):
                return "Drawer not found — key: \(sampleId), matched \(candidates) candidate(s)."
            case let .commitFailed(sampleId, underlying):
                return "Failed to copy file for sample \(sampleId): \(underlying.localizedDescription)"
            case let .destinationArtifactMismatch(sampleId, measurementExists, _):
                let present = measurementExists ? "measurement file" : "sidecar"
                let missing = measurementExists ? "sidecar" : "measurement file"
                return "Destination for sample \(sampleId) has a \(present) but no \(missing) — refusing to apply without repair."
            }
        }
    }

    /// The single "can this draft be applied" judgement (replaces three scattered copies).
    /// It does not depend on any adapter or on channels being confirmed: only on valid targets.
    static func canApplyV2(draft: PendingImportConfirmationDraft?, isValidActiveSample: (String) -> Bool) -> Bool {
        guard let targets = draft?.v2Targets, !targets.isEmpty else { return false }
        var seen = Set<String>()
        for target in targets {
            let uid = target.sampleUID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty, seen.insert(uid).inserted else { return false }
            // A stored target stays applicable even if its Sample was trashed since: only unfinished ones need a live Sample.
            if !target.isIngested, !isValidActiveSample(uid) { return false }
        }
        return true
    }

    func apply(
        pending: SpinLabDomain.PendingImport,
        targets: [SpinLabDomain.RouteTarget],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL,
        draft: PendingImportConfirmationDraft? = nil,
        workflowDefinitions: [WorkflowDefinition] = []
    ) throws -> InboxArchiveApplyResult {
        switch LibraryLayoutRouter.resolve(rootURL: libraryRootURL) {
        case .v1, .uninitialized:
            break
        case let .invalid(error):
            throw error
        case .v2:
            return try applyV2(
                pending: pending,
                targets: targets,
                libraryIndex: libraryIndex,
                libraryStore: libraryStore,
                libraryRootURL: libraryRootURL,
                draft: draft,
                workflowDefinitions: workflowDefinitions
            )
        }
        try LibraryLayoutRouter.requireV1ArtifactWriteAllowed(
            rootURL: libraryRootURL,
            operation: "InboxArchiveApply"
        )
        let sourceURL = URL(fileURLWithPath: pending.sourceFilePath)
        let samplesByID = Dictionary(uniqueKeysWithValues: libraryIndex.samples.map { ($0.id, $0) })
        var targetDrawers: [String] = []
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            writeAuditEvent(
                pending: pending,
                sourceURL: sourceURL,
                targetDrawers: resolvedTargetDrawers(
                    for: targets,
                    samplesByID: samplesByID,
                    libraryStore: libraryStore,
                    libraryRootURL: libraryRootURL
                ),
                result: "failed",
                metadata: ["reason": InboxArchiveApplyError.sourceFileNotFound.localizedDescription],
                libraryRootURL: libraryRootURL
            )
            throw InboxArchiveApplyError.sourceFileNotFound
        }

        var transaction = LibraryWriteTransaction()
        var copiedTargetCount = 0
        var skippedExistingTargetCount = 0
        // Resolved once against the original Inbox source file, before any copy/move,
        // and reused for every RouteTarget derived from this same file.
        let measurementTimestamp = MeasurementTimestampResolver().resolve(fileURL: sourceURL)

        do {
            for target in targets {
                guard let sample = samplesByID[target.sampleId] else {
                    throw InboxArchiveApplyError.drawerNotFound(sampleId: target.sampleId, candidates: 0)
                }

                let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
                guard FileManager.default.fileExists(atPath: drawerRoot.path) else {
                    throw InboxArchiveApplyError.drawerNotFound(sampleId: target.sampleId, candidates: 0)
                }
                let workflow = resolvedWorkflow(
                    draft: draft,
                    pending: pending,
                    workflowDefinitions: workflowDefinitions
                )
                let destinationDirectory = drawerRoot.appending(
                    path: destinationSubpath(workflowName: workflow),
                    directoryHint: .isDirectory
                )
                let destinationURL = destinationDirectory.appending(
                    path: sourceURL.lastPathComponent,
                    directoryHint: .notDirectory
                )
                let drawerSummary = relativePath(drawerRoot, from: libraryRootURL)
                if !targetDrawers.contains(drawerSummary) {
                    targetDrawers.append(drawerSummary)
                }
                let sidecarURL = destinationDirectory.appending(
                    path: sourceURL.lastPathComponent + ".spinlab.json",
                    directoryHint: .notDirectory
                )
                let measurementExists = FileManager.default.fileExists(atPath: destinationURL.path)
                let sidecarExists = FileManager.default.fileExists(atPath: sidecarURL.path)
                switch (measurementExists, sidecarExists) {
                case (true, true):
                    skippedExistingTargetCount += 1
                    continue
                case (false, false):
                    break
                case (true, false), (false, true):
                    // Measurement + sidecar are one persistence pair. Seeing only one
                    // of them at the destination means a prior write left an
                    // inconsistent pair (or something external touched the drawer).
                    // Fail closed rather than silently accepting/overwriting it.
                    throw InboxArchiveApplyError.destinationArtifactMismatch(
                        sampleId: target.sampleId,
                        measurementExists: measurementExists,
                        sidecarExists: sidecarExists
                    )
                }
                try transaction.prepare(sourceURL: sourceURL, destinationURL: destinationURL)
                let sidecar = buildSidecar(
                    pending: pending,
                    target: target,
                    draft: draft,
                    workflow: workflow ?? "",
                    workflowDefinitions: workflowDefinitions,
                    measurementTimestamp: measurementTimestamp
                )
                try transaction.prepareSidecar(sidecar, destinationURL: sidecarURL)
                copiedTargetCount += 1
            }

            if copiedTargetCount > 0 {
                try transaction.commit()
            }

            let result = InboxArchiveApplyResult(
                copiedTargetCount: copiedTargetCount,
                skippedExistingTargetCount: skippedExistingTargetCount
            )
            writeAuditEvent(
                pending: pending,
                sourceURL: sourceURL,
                targetDrawers: targetDrawers,
                result: result.allTargetsSkipped ? "skipped_existing" : "applied",
                metadata: [
                    "copiedTargetCount": "\(result.copiedTargetCount)",
                    "skippedExistingTargetCount": "\(result.skippedExistingTargetCount)"
                ],
                libraryRootURL: libraryRootURL
            )
            return result
        } catch let error as InboxArchiveApplyError {
            // Reached before `transaction.commit()` was ever called (e.g. drawer
            // not found, destination mismatch) — only staged, uncommitted temp
            // files can exist, never real destinations.
            let rollbackFailure = transaction.rollback()
            logRollbackOutcome(rollbackFailure, pendingID: pending.id)
            writeAuditEvent(
                pending: pending,
                sourceURL: sourceURL,
                targetDrawers: targetDrawers.isEmpty
                    ? resolvedTargetDrawers(
                        for: targets,
                        samplesByID: samplesByID,
                        libraryStore: libraryStore,
                        libraryRootURL: libraryRootURL
                    )
                    : targetDrawers,
                result: "failed",
                metadata: auditFailureMetadata(reason: error.localizedDescription, rollbackFailure: rollbackFailure),
                libraryRootURL: libraryRootURL
            )
            throw error
        } catch {
            // A `LibraryWriteTransaction.CommitFailure` means `transaction.commit()`
            // already ran its own rollback internally — calling `rollback()` again
            // here would be a no-op on already-cleared state and would silently
            // lose the rollback outcome it already computed. Extract it instead.
            let rollbackFailure: LibraryWriteTransaction.RollbackFailure?
            let appError: AppError
            if let commitFailure = error as? LibraryWriteTransaction.CommitFailure {
                rollbackFailure = commitFailure.rollbackFailure
                appError = AppError.from(commitFailure.underlyingError, fallback: "Failed to commit file writes.")
            } else {
                rollbackFailure = transaction.rollback()
                appError = AppError.from(error, fallback: "Failed to commit file writes.")
            }
            logRollbackOutcome(rollbackFailure, pendingID: pending.id)
            writeAuditEvent(
                pending: pending,
                sourceURL: sourceURL,
                targetDrawers: targetDrawers.isEmpty
                    ? resolvedTargetDrawers(
                        for: targets,
                        samplesByID: samplesByID,
                        libraryStore: libraryStore,
                        libraryRootURL: libraryRootURL
                    )
                    : targetDrawers,
                result: "failed",
                metadata: auditFailureMetadata(reason: appError.localizedDescription, rollbackFailure: rollbackFailure),
                libraryRootURL: libraryRootURL
            )
            throw InboxArchiveApplyError.commitFailed(
                sampleId: targets.first?.sampleId ?? "unknown",
                underlying: appError
            )
        }
    }

    /// Distinguishes, in both the app log and the audit trail, "apply failed +
    /// rollback completed" from "apply failed + rollback incomplete" — the
    /// latter means a real artifact from this attempt may still be sitting at
    /// its destination despite the apply being reported as failed.
    private func logRollbackOutcome(_ rollbackFailure: LibraryWriteTransaction.RollbackFailure?, pendingID: UUID) {
        guard let rollbackFailure else { return }
        AppLogger.shared.error(
            .import,
            "rollback incomplete after apply failure (pending \(pendingID)): \(rollbackFailure.errorDescription ?? "unknown")"
        )
    }

    private func auditFailureMetadata(
        reason: String,
        rollbackFailure: LibraryWriteTransaction.RollbackFailure?
    ) -> [String: String] {
        var metadata = ["reason": reason]
        guard let rollbackFailure else {
            metadata["rollbackIncomplete"] = "false"
            return metadata
        }
        metadata["rollbackIncomplete"] = "true"
        if !rollbackFailure.survivingDestinationURLs.isEmpty {
            metadata["rollbackSurvivingDestinations"] = rollbackFailure.survivingDestinationURLs
                .map(\.path)
                .joined(separator: ", ")
        }
        if !rollbackFailure.survivingTemporaryURLs.isEmpty {
            metadata["rollbackSurvivingTempFiles"] = rollbackFailure.survivingTemporaryURLs
                .map(\.path)
                .joined(separator: ", ")
        }
        return metadata
    }

    private func writeAuditEvent(
        pending: SpinLabDomain.PendingImport,
        sourceURL: URL,
        targetDrawers: [String],
        result: String,
        metadata: [String: String],
        libraryRootURL: URL
    ) {
        let event = AuditEvent(
            eventID: UUID().uuidString,
            timestamp: Self.auditTimestampFormatter.string(from: Date()),
            action: "apply_import",
            sourceFileName: pending.fileName,
            sourceFilePath: sourceURL.path,
            targetDrawers: targetDrawers,
            result: result,
            metadata: metadata
        )
        auditLogger.logImportEvent(event, libraryRootURL: libraryRootURL)
    }

    private func resolvedTargetDrawers(
        for targets: [SpinLabDomain.RouteTarget],
        samplesByID: [String: LibrarySample],
        libraryStore: LibraryStore,
        libraryRootURL: URL
    ) -> [String] {
        var drawers: [String] = []
        for target in targets {
            guard let sample = samplesByID[target.sampleId] else {
                continue
            }
            let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
            let drawerPath = relativePath(drawerRoot, from: libraryRootURL)
            if !drawers.contains(drawerPath) {
                drawers.append(drawerPath)
            }
        }
        return drawers
    }

    private func relativePath(_ url: URL, from rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let absolute = url.standardizedFileURL.path
        if absolute.hasPrefix(rootPath + "/") {
            return String(absolute.dropFirst(rootPath.count + 1))
        }
        return absolute
    }

    private func destinationSubpath(workflowName: String?) -> String {
        LibraryDestinationSubpath.subpath(workflowName: workflowName)
    }

    private func buildSidecar(
        pending: SpinLabDomain.PendingImport,
        target: SpinLabDomain.RouteTarget,
        draft: PendingImportConfirmationDraft?,
        workflow: String,
        workflowDefinitions: [WorkflowDefinition],
        measurementTimestamp: SidecarMeasurementTimestamp
    ) -> SpinLabFileSidecar {
        let matchedDefinition = workflowDefinition(
            for: workflow,
            workflowDefinitions: workflowDefinitions
        )
        let workflowDisplayName = matchedDefinition?.displayName ?? workflow

        let loadResult = ruleProvider.loadResult()
        let snapshot = SidecarCompositionUseCase.buildRuleSnapshot(
            hints: pending.parsedHints,
            ruleSetFingerprint: loadResult.ruleSetFingerprint,
            ruleSetVersion: loadResult.ruleSetVersion,
            evaluatedAt: .now
        )

        // Compute draft-based overrides: values the user explicitly entered that
        // differ from what the rules detected → captured as userOverrides.
        let draftConditions = computeDraftConditions(
            pending: pending,
            draft: draft,
            matchedDefinition: matchedDefinition
        )
        var overrideConditions: [String: ManualValueOverride] = [:]
        for (id, draftValue) in draftConditions {
            let ruleValue = snapshot.fields.conditions[id]?.value
            if ruleValue != draftValue {
                overrideConditions[id] = ManualValueOverride(value: draftValue, reason: "manual", at: .now)
            }
        }

        var sidecar = SidecarCompositionUseCase.composeSidecarV2(
            base: SidecarCompositionBase(
                workflow: workflow,
                autoDetectedWorkflow: pending.parsedHints.workflowID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? workflow,
                workflowDisplayName: workflowDisplayName,
                channels: target.channels,
                sourceFilePath: pending.sourceFilePath,
                existingSidecar: nil,
                // Final RouteTarget.sampleId — already guaranteed to equal the canonical
                // LibrarySample.id. Not re-parsed or re-normalized here.
                sampleKey: target.sampleId,
                measurementTimestamp: measurementTimestamp
            ),
            snapshot: snapshot,
            preserveUserOverrides: false,
            now: .now
        )
        sidecar.userOverrides = SidecarUserOverrides(conditions: overrideConditions)
        return sidecar
    }

    private func computeDraftConditions(
        pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft?,
        matchedDefinition: WorkflowDefinition?
    ) -> [String: String] {
        let source: [String: String]
        if let draft {
            // Draft present: trust user-edited values only.
            source = draft.conditionValues
        } else {
            // Draft absent: fall back to parser baseline.
            source = ConditionFieldCatalog.conditionValues(from: pending.parsedHints)
        }
        let normalized = normalizedConditionValues(from: source)
        guard let definition = matchedDefinition else { return normalized }
        let selectedIDs = Set(definition.conditionFields.map(\.definitionID))
        return normalized.filter { selectedIDs.contains($0.key) }
    }

    private func normalizedConditionValues(from values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { partialResult, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partialResult[key] = value
        }
    }

    private func resolvedWorkflow(
        draft: PendingImportConfirmationDraft?,
        pending: SpinLabDomain.PendingImport,
        workflowDefinitions: [WorkflowDefinition]
    ) -> String? {
        let candidate: String?
        if let draft {
            // Boundary rule: with an explicit draft, do not silently fall back
            // to parser workflow.
            candidate = draft.workflowID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            candidate = pending.parsedHints.workflowID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        guard let candidate else { return nil }
        return workflowDefinition(for: candidate, workflowDefinitions: workflowDefinitions)?.id ?? candidate
    }

    private func workflowDefinition(
        for workflowID: String,
        workflowDefinitions: [WorkflowDefinition]
    ) -> WorkflowDefinition? {
        let normalized = workflowID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return workflowDefinitions.first {
            $0.id.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }
}

private extension InboxArchiveApplyService {
    static let auditTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension InboxArchiveApplyService {
    func applyV2(
        pending: SpinLabDomain.PendingImport,
        targets: [SpinLabDomain.RouteTarget],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL,
        draft: PendingImportConfirmationDraft?,
        workflowDefinitions: [WorkflowDefinition]
    ) throws -> InboxArchiveApplyResult {
        let workflow = resolvedWorkflow(draft: draft, pending: pending, workflowDefinitions: workflowDefinitions)
        let v2Targets = draft?.v2Targets ?? []
        guard !v2Targets.isEmpty else {
            // Without an explicit V2 target and without any workflow this is a V1-style apply, which V2 refuses as before.
            if workflow == nil { throw LibraryLayoutError.v2UnsupportedOperation("InboxArchiveApply(no V2 target)") }
            throw LibraryAssetError.invalidSample("no target sample selected")
        }
        let sourceURL = URL(fileURLWithPath: pending.sourceFilePath)
        let assetService = makeAssetService(libraryStore)
        let context = ingestContext(pending: pending, sourceURL: sourceURL, draft: draft, workflow: workflow)
        let coordinator = V2SourceStandardizationCoordinator(service: assetService, rootURL: libraryRootURL)
        // Read the applied preset once, before any step; unreadable or off means no intent (fail-closed).
        let intent = coordinator.currentAutoPlotIntent(workflowID: workflow)

        var results: [V2TargetApplyResult] = []
        var triggers: [AutoPlotTrigger] = []
        for target in v2Targets {
            let uid = target.sampleUID.trimmingCharacters(in: .whitespacesAndNewlines)
            var result = V2TargetApplyResult(sampleUID: uid, ingest: .failed(""), standardize: .notReached)

            // ① Ingest: replays the stored receipt for an already committed target (no external file needed).
            let receipt: SourceReceipt
            do {
                receipt = try assetService.ingestSource(
                    SourceIngestRequest(
                        sourceFileURL: sourceURL, targetSampleUID: uid, operationID: target.ingestOperationID,
                        context: context,
                        effectiveChannels: target.effectiveChannelIDs.map { $0.map { EffectiveChannel(id: $0) } },
                        reuseSourceID: target.reuseSourceID
                    ),
                    rootURL: libraryRootURL
                )
                result.ingest = .applied(sourceID: receipt.sourceID)
                writeAuditEvent(
                    pending: pending, sourceURL: sourceURL, targetDrawers: [uid], result: "applied",
                    metadata: ["stage": "ingest", "sourceID": receipt.sourceID, "reusedSource": "\(receipt.reusedSource)", "sampleUID": uid],
                    libraryRootURL: libraryRootURL
                )
            } catch {
                result.ingest = .failed(error.localizedDescription)
                writeAuditEvent(
                    pending: pending, sourceURL: sourceURL, targetDrawers: [uid], result: "failed",
                    metadata: ["stage": "ingest", "reason": error.localizedDescription], libraryRootURL: libraryRootURL
                )
                results.append(result)
                continue
            }

            // ② Standardize from the stored copy (adapter by container format) and ③ the AFM follow-up.
            let standardizeOp = LibraryAssetService.standardizeOperationID(forIngest: target.ingestOperationID)
            do {
                let outcome = try coordinator.standardize(
                    sourceID: receipt.sourceID, sampleUID: uid, operationID: standardizeOp, fileName: sourceURL.lastPathComponent,
                    confirmedWorkflowID: context.workflowOrigin.isConfirmed ? context.workflowID : nil, autoPlotIntent: intent
                )
                switch outcome.result {
                case .standardized: result.standardize = .standardized
                case let .notStandardized(code, _): result.standardize = .notStandardized(code: code)
                }
                if let trigger = outcome.autoPlotTrigger {
                    triggers.append(trigger)
                    result.plot = .queued
                }
                writeAuditEvent(
                    pending: pending, sourceURL: sourceURL, targetDrawers: [uid], result: "applied",
                    metadata: ["stage": "standardize", "sourceID": receipt.sourceID, "outcome": "\(outcome.result)"],
                    libraryRootURL: libraryRootURL
                )
            } catch {
                result.standardize = .pending(error.localizedDescription)
                writeAuditEvent(
                    pending: pending, sourceURL: sourceURL, targetDrawers: [uid], result: "failed",
                    metadata: ["stage": "standardize", "sourceID": receipt.sourceID, "reason": error.localizedDescription],
                    libraryRootURL: libraryRootURL
                )
            }
            results.append(result)
        }
        return InboxArchiveApplyResult(
            copiedTargetCount: results.filter { $0.sourceID != nil }.count,
            skippedExistingTargetCount: 0,
            autoPlotTriggers: triggers,
            v2TargetResults: results
        )
    }

    /// Context captured for ingest: values equal to what the file name rules proposed are `rule`,
    /// anything the user typed or changed is `manual`; unresolved stays unknown.
    func ingestContext(
        pending: SpinLabDomain.PendingImport, sourceURL: URL, draft: PendingImportConfirmationDraft?, workflow: String?
    ) -> SourceContextInput {
        let hints = pending.parsedHints
        var conditions: [String: ContextConditionValue] = [:]
        for (key, raw) in (draft?.conditionValues ?? [:]).sorted(by: { $0.key < $1.key }) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            conditions[key] = ContextConditionValue(value: value, origin: hints.conditionValues[key] == value ? .rule : .manual)
        }
        let timestamp = MeasurementTimestampResolver().resolve(fileURL: sourceURL)
        let measuredOrigin: ContextOrigin
        switch timestamp.provenance {
        case .instrumentHeader, .filename: measuredOrigin = .rule
        case .filesystemFallback: measuredOrigin = .fallback
        case .unknown: measuredOrigin = .unknown
        }
        let workflowOrigin: ContextOrigin = workflow == nil ? .unknown
            : (hints.workflowID?.lowercased() == workflow?.lowercased() ? .rule : .manual)
        return SourceContextInput(
            workflowID: workflow, workflowOrigin: workflowOrigin, conditions: conditions,
            measuredAt: timestamp.value.map { ISO8601DateFormatter().string(from: $0) },
            measuredAtOrigin: measuredOrigin, interpretation: timestamp.rawText.map { ["measuredAtText": $0] } ?? [:],
            legacyPath: pending.originalFilePath ?? pending.sourceFilePath
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
