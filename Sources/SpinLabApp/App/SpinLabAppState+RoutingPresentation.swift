import Foundation

extension SpinLabAppState {

    var selectedPendingImport: SpinLabDomain.PendingImport? {
        inboxFeatureStore.pendingImports.first { $0.id == selectedPendingImportID }
    }

    var selectedArchivedRecord: SpinLabDomain.ArchivedRecord? {
        workbenchFeatureStore.selectedArchivedRecord()
    }

    var workbenchTitle: String {
        if let archived = selectedArchivedRecord {
            return archived.measurement.name
        }

        if let pending = selectedPendingImport {
            return pending.fileName
        }

        return "No measurement selected"
    }

    var defaultViewDisplayName: String {
        viewExtension.displayName
    }

    var pendingDrawerMatchByID: [UUID: Bool] {
        Dictionary(uniqueKeysWithValues: inboxFeatureStore.pendingImports.map { pending in
            let presentation = pendingRoutePresentation(for: pending)
            return (pending.id, presentation.isLibraryMatched)
        })
    }

    var knownProjectNames: [String] {
        let archivedNames = workbenchFeatureStore.archivedRecords.compactMap { $0.project?.name }
        let catalogNames = workbenchFeatureStore.projectCatalog.map(\.name)
        return Array(Set(archivedNames + catalogNames)).sorted()
    }

    var selectedPendingImportID: UUID? {
        get { inboxFeatureStore.selectedPendingImportID }
        set {
            inboxFeatureStore.selectedPendingImportID = newValue
            persistInteractionSnapshotIfReady()
        }
    }

    func defaultConfirmationDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        let resolvedSampleID = pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
        var draft = importPipeline.metadataExtension.defaultConfirmationDraft(
            pending: pending,
            suggestedProjectName: suggestedProject(for: pending)?.name,
            registryLookup: registryLookup(for: pending),
            fallbackSampleID: resolvedSampleID
        )
        let rawDraftWorkflow = draft.workflowID.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.workflowID = canonicalWorkflowID(from: rawDraftWorkflow) ?? rawDraftWorkflow
        return draft
    }

    func pendingDisplayDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        defaultConfirmationDraft(for: pending)
    }

    func pendingRoutePresentation(for pending: SpinLabDomain.PendingImport) -> PendingRoutePresentation {
        let substrate = substrateWarning(for: pending, registryLookup: registryLookup(for: pending))
        return inboxFeatureStore.pendingRoutePresentation(
            for: pending,
            substrateWarning: substrate
        )
    }

    func pendingRoutePresentation(
        for pending: SpinLabDomain.PendingImport,
        routingDraft: PendingRoutingDraft,
        sampleName: String
    ) -> PendingRoutePresentation {
        let substrate = substrateWarning(for: pending, registryLookup: registryLookup(for: pending))
        return inboxFeatureStore.previewPendingRoutePresentation(
            for: pending,
            routingDraft: routingDraft,
            sampleName: sampleName,
            substrateWarning: substrate
        )
    }

    func pendingRoutePresentationByID() -> [UUID: PendingRoutePresentation] {
        inboxFeatureStore.pendingRoutePresentationByID(
            substrateWarning: { [weak self] pending in
                guard let self else { return nil }
                return self.substrateWarning(for: pending, registryLookup: self.registryLookup(for: pending))
            }
        )
    }

    func pendingDisplayWarningItems(for pending: SpinLabDomain.PendingImport) -> [PendingDisplayWarning] {
        pendingRoutePresentation(for: pending).warningItems
    }

    func pendingDisplayInfoTags(for pending: SpinLabDomain.PendingImport) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: pending.parsedHints.measurementTags.compactMap { normalized($0) })
        tags.append(contentsOf: pending.parsedHints.substrateTags.compactMap { normalized($0) })

        if let rotation = normalized(pending.parsedHints.rotationHint) {
            tags.append("rotation: \(rotation)")
        }

        var seen: Set<String> = []
        return tags.filter { tag in
            let key = tag.lowercased()
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    func pendingDisplayAutoValues(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        let resolvedSampleID = pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)

        return PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? resolvedSampleID ?? "",
            sampleName: pending.parsedHints.sampleName ?? "",
            measurementName: pending.parsedHints.measurementName ?? pending.fileName,
            workflowID: {
                let raw = pending.parsedHints.workflowID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return canonicalWorkflowID(from: raw) ?? raw
            }(),
            conditionValues: parsedHintsConditionValues(from: pending.parsedHints),
            selectedExistingProjectName: suggestedProject(for: pending)?.name ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
    }

    func pendingRoutePlan(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RoutePlan {
        inboxFeatureStore.pendingRoutePlan(for: pending)
    }

    func pendingRoutingPreviewSnapshot(
        for pending: SpinLabDomain.PendingImport,
        routingDraft: PendingRoutingDraft,
        sampleName: String
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        inboxFeatureStore.previewPendingRoutingSnapshot(
            for: pending,
            routingDraft: routingDraft,
            sampleName: sampleName
        )
    }

    func pendingRouteStatus(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RouteStatus {
        inboxFeatureStore.pendingRouteStatus(for: pending)
    }

    func hasSavedRoutingDraft(for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxFeatureStore.hasSavedRoutingDraft(for: pending)
    }

    func routingDraft(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxFeatureStore.routingDraft(for: pending)
    }

    func routingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxFeatureStore.routingDraftBaseline(for: pending)
    }

    func isRoutingDraftDirty(_ draft: PendingRoutingDraft, for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxFeatureStore.isRoutingDraftDirty(draft, for: pending)
    }

    func saveRoutingDraft(_ draft: PendingRoutingDraft, for pendingID: UUID) {
        inboxFeatureStore.saveRoutingDraft(draft, for: pendingID)
        bumpAppStateRevision()
    }

    func pendingTagReadiness(
        for pending: SpinLabDomain.PendingImport,
        draftOverride: PendingImportConfirmationDraft? = nil
    ) -> PendingTagReadiness {
        guard pendingRouteStatus(for: pending) == .libraryMatched else {
            return .notLibraryMatched
        }
        let missing = pendingMissingRequiredTagLabels(for: pending, draftOverride: draftOverride)
        return missing.isEmpty ? .allGood : .tagsMissing(missing)
    }

    func pendingMissingRequiredTagLabels(
        for pending: SpinLabDomain.PendingImport,
        draftOverride: PendingImportConfirmationDraft? = nil
    ) -> [String] {
        let draft = effectivePendingDraft(for: pending, draftOverride: draftOverride)
        let workflowID = canonicalWorkflowID(from: draft.workflowID)
            ?? canonicalWorkflowID(from: pending.parsedHints.workflowID)
        guard let workflowID,
              let definition = workflowDefinitions.first(where: {
                  $0.id.caseInsensitiveCompare(workflowID) == .orderedSame
              }) else {
            return []
        }

        return definition.conditionFields.compactMap { field in
            let rawValue = draft.conditionValues[field.definitionID]
            guard isMissingConditionValue(rawValue) else {
                return nil
            }
            return workbenchFeatureStore.conditionLabel(for: field.definitionID)
        }
    }

    func hasAnyAllGoodPendingImports() -> Bool {
        let workspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        return inboxFeatureStore.pendingImports.contains { pending in
            let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
            let draftOverride = workspaceByPendingID[key]?.draft
            if case .allGood = pendingTagReadiness(for: pending, draftOverride: draftOverride) {
                return true
            }
            return false
        }
    }

    func registryLookup(for pending: SpinLabDomain.PendingImport) -> SampleRegistryLookupResult? {
        if let sampleID = pending.parsedHints.sampleIDs.first {
            return sampleRegistry.lookup(sampleID: sampleID)
        }
        return sampleRegistry.lookup(from: pending.fileName)
    }

    func parsedSampleIDFromFilename(for pending: SpinLabDomain.PendingImport) -> String? {
        pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
    }

    func parsedPrefixFromFilename(for pending: SpinLabDomain.PendingImport) -> String? {
        guard let sampleID = parsedSampleIDFromFilename(for: pending) else {
            return nil
        }
        return SampleIDParser.extractPrefix(fromSampleID: sampleID)
    }

    func resolvedSampleDisplayName(for pending: SpinLabDomain.PendingImport) -> String? {
        pending.parsedHints.sampleName
            ?? pending.parsedHints.batchName
            ?? pending.parsedHints.sampleIDs.first
            ?? sampleRegistry.sampleID(from: pending.fileName)
    }

    func clearActiveAlert() {
        activeAlert = nil
    }

    func presentAlert(title: String, message: String) {
        activeAlert = AppAlertState(title: title, message: message)
    }

    func present(error: AppError, title: String) {
        activeAlert = AppAlertState(
            title: title,
            message: error.localizedDescription
        )
    }

    func exportAuditTrail(to destinationURL: URL, note: String? = nil) throws -> AppLogger.AuditTrailExportSummary {
        var context: [String: String] = [
            "workflow": workflow.rawValue,
            "appVersion": AppVersion.current,
            "routingRuleVersion": "\(inboxFeatureStore.routingRuleVersion)",
            "routingRuleSource": inboxFeatureStore.routingRuleSourceLabel,
            "routingRulePath": inboxFeatureStore.routingRuleSourcePath,
            "routingRuleFingerprint": inboxFeatureStore.routingRuleFingerprint,
            "routingRuleHashPrefix": inboxFeatureStore.routingRuleHashPrefix,
            "pendingImportCount": "\(inboxFeatureStore.pendingImports.count)",
            "archivedRecordCount": "\(workbenchFeatureStore.archivedRecords.count)",
            "selectedArea": selectedArea.rawValue
        ]
        if let selectedPendingImportID {
            context["selectedPendingImportID"] = selectedPendingImportID.uuidString
        }
        if let selectedArchivedRecordID = workbenchFeatureStore.selectedArchivedRecordID {
            context["selectedArchivedRecordID"] = selectedArchivedRecordID.uuidString
        }
        if let note = normalized(note) {
            context["note"] = note
        }
        do {
            let summary = try appLogger.exportAuditTrail(to: destinationURL, context: context)
            appLogger.info(.system, "Audit trail exported", metadata: [
                "entryCount": "\(summary.entryCount)",
                "workflow": workflow.rawValue
            ])
            return summary
        } catch {
            appLogger.error(.system, "Audit trail export failed", metadata: [
                "reason": error.localizedDescription,
                "workflow": workflow.rawValue
            ])
            throw error
        }
    }

    func recomputedParsedHints(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints {
        let fileManager = FileManager.default
        let parseURL: URL

        if let original = pending.originalFilePath,
           fileManager.fileExists(atPath: original) {
            parseURL = URL(fileURLWithPath: original)
        } else {
            parseURL = URL(fileURLWithPath: pending.fileName)
        }

        return importPipeline.metadataExtension.parseFilename(from: parseURL)
    }

    func effectivePendingDraft(
        for pending: SpinLabDomain.PendingImport,
        draftOverride: PendingImportConfirmationDraft?
    ) -> PendingImportConfirmationDraft {
        if let draftOverride {
            return draftOverride
        }
        let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
        if let workspaceDraft = interactionValue(\.inboxWorkspaceByPendingID)[key]?.draft {
            return workspaceDraft
        }
        return pendingDisplayDraft(for: pending)
    }

    func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func canonicalWorkflowID(from rawWorkflow: String?) -> String? {
        guard let normalizedRaw = normalized(rawWorkflow) else { return nil }
        return workflowDefinitions.first(where: {
            $0.id.caseInsensitiveCompare(normalizedRaw) == .orderedSame
        })?.id
    }

    private func makeArchivedRecord(
        from pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> SpinLabDomain.ArchivedRecord {
        let context = ArchivedRecordBuildContext(
            pending: pending,
            draft: draft,
            registryLookup: registryLookup,
            domainContext: archivedRecordDomainContext
        )
        return importPipeline.workflowExtension.createArchivedRecord(context: context)
    }

    private func isMissingConditionValue(_ value: String?) -> Bool {
        guard let normalizedValue = normalized(value) else {
            return true
        }
        return normalizedValue.caseInsensitiveCompare("UNKNOWN") == .orderedSame
    }

    private func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String? {
        archivedRecordResolverService.metadataValue(in: lookup, keys: keys)
    }

    private func measurementNotes(
        for pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> String {
        archivedRecordResolverService.measurementNotes(
            for: pending,
            draft: draft,
            registryLookup: registryLookup
        )
    }

    private func substrateWarning(
        for pending: SpinLabDomain.PendingImport,
        registryLookup: SampleRegistryLookupResult?
    ) -> String? {
        archivedRecordResolverService.substrateWarning(
            for: pending,
            registryLookup: registryLookup
        )
    }

    private func parsedHintsConditionValues(from hints: SpinLabDomain.ParsedFilenameHints) -> [String: String] {
        ConditionFieldCatalog.conditionValues(from: hints)
    }

    private func suggestedProject(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.Project? {
        workbenchFeatureStore.suggestedProject(for: pending)
    }
}
