import Foundation

struct InboxArchiveApplyResult: Equatable {
    var copiedTargetCount: Int
    var skippedExistingTargetCount: Int

    var allTargetsSkipped: Bool {
        copiedTargetCount == 0 && skippedExistingTargetCount > 0
    }
}

struct InboxArchiveApplyService {
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
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw InboxArchiveApplyError.sourceFileNotFound
        }

        let samplesByID = Dictionary(uniqueKeysWithValues: libraryIndex.samples.map { ($0.id, $0) })
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

            return InboxArchiveApplyResult(
                copiedTargetCount: copiedTargetCount,
                skippedExistingTargetCount: skippedExistingTargetCount
            )
        } catch let error as InboxArchiveApplyError {
            try? transaction.rollback()
            throw error
        } catch {
            try? transaction.rollback()
            throw InboxArchiveApplyError.commitFailed(
                sampleId: targets.first?.sampleId ?? "unknown",
                underlying: AppError.from(error, fallback: "Failed to commit file writes.")
            )
        }
    }

    private func destinationSubpath(workflowName: String?) -> String {
        let sanitized = workflowName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        if let workflow = sanitized, !workflow.isEmpty {
            return "measurements/\(workflow)"
        }
        return "measurements/General"
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
        // Use registry displayName as the human-readable label; fall back to id.
        let workflowDisplayName = matchedDefinition?.displayName ?? workflow

        let sourceConditions = effectiveConditionValues(pending: pending, draft: draft)
        let conditions: [String: String]
        if let definition = matchedDefinition {
            // Only persist non-empty, parsed/confirmed condition values.
            // Do not hard-fill empty placeholders for missing fields.
            let selectedIDs = definition.conditionFields.map(\.definitionID)
            conditions = selectedIDs.reduce(into: [:]) { result, definitionID in
                guard let value = sourceConditions[definitionID], !value.isEmpty else { return }
                result[definitionID] = value
            }
        } else {
            conditions = sourceConditions
        }

        return SpinLabFileSidecar(
            workflow: workflow,
            workflowDisplayName: workflowDisplayName,
            conditions: conditions,
            channels: target.channels,
            sourceFilePath: pending.sourceFilePath,
            appliedAt: .now
        )
    }

    private func normalizedConditionValues(from values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { partialResult, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partialResult[key] = value
        }
    }

    private func effectiveConditionValues(
        pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft?
    ) -> [String: String] {
        // Boundary rule:
        // - draft present: trust user-edited values only.
        // - draft absent: fall back to parser baseline.
        if let draft {
            return normalizedConditionValues(from: draft.conditionValues)
        }
        let parsedConditions = ConditionFieldCatalog.conditionValues(from: pending.parsedHints)
        return normalizedConditionValues(from: parsedConditions)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
