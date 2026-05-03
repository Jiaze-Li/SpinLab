import Foundation

struct InboxArchiveApplyResult: Equatable {
    var copiedTargetCount: Int
    var skippedExistingTargetCount: Int

    var allTargetsSkipped: Bool {
        copiedTargetCount == 0 && skippedExistingTargetCount > 0
    }
}

struct InboxArchiveApplyService {
    private let auditLogger: any AuditLogging
    private let ruleProvider: any SpinLabRuleProviding

    init(auditLogger: (any AuditLogging)? = nil, ruleProvider: (any SpinLabRuleProviding)? = nil) {
        self.auditLogger = auditLogger ?? AuditLogger.shared
        self.ruleProvider = ruleProvider ?? SpinLabRuleProvider.shared
    }

    enum InboxArchiveApplyError: LocalizedError {
        case sourceFileNotFound
        case drawerNotFound(sampleId: String, candidates: Int)
        case commitFailed(sampleId: String, underlying: AppError)

        var errorDescription: String? {
            switch self {
            case .sourceFileNotFound:
                return "Pending source file does not exist."
            case let .drawerNotFound(sampleId, candidates):
                return "Drawer not found — key: \(sampleId), matched \(candidates) candidate(s)."
            case let .commitFailed(sampleId, underlying):
                return "Failed to copy file for sample \(sampleId): \(underlying.localizedDescription)"
            }
        }
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
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    skippedExistingTargetCount += 1
                    continue
                }
                try transaction.prepare(sourceURL: sourceURL, destinationURL: destinationURL)
                let sidecarURL = destinationDirectory.appending(
                    path: sourceURL.lastPathComponent + ".spinlab.json",
                    directoryHint: .notDirectory
                )
                let sidecar = buildSidecar(
                    pending: pending,
                    target: target,
                    draft: draft,
                    workflow: workflow ?? "",
                    workflowDefinitions: workflowDefinitions
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
            do { try transaction.rollback() } catch let rollbackError {
                AppLogger.shared.error(.import, "rollback failed after apply error: \(rollbackError)")
            }
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
                metadata: ["reason": error.localizedDescription],
                libraryRootURL: libraryRootURL
            )
            throw error
        } catch {
            do { try transaction.rollback() } catch let rollbackError {
                AppLogger.shared.error(.import, "rollback failed after apply error: \(rollbackError)")
            }
            let appError = AppError.from(error, fallback: "Failed to commit file writes.")
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
                metadata: ["reason": appError.localizedDescription],
                libraryRootURL: libraryRootURL
            )
            throw InboxArchiveApplyError.commitFailed(
                sampleId: targets.first?.sampleId ?? "unknown",
                underlying: appError
            )
        }
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
        workflowDefinitions: [WorkflowDefinition]
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
                workflowDisplayName: workflowDisplayName,
                channels: target.channels,
                sourceFilePath: pending.sourceFilePath,
                existingSidecar: nil
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
