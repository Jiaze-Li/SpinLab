import Foundation

extension SpinLabAppState {

    func load() {
        applyPendingImportsProjection(inboxFeatureStore.pendingImports)
        applyArchivedRecordsProjection(workbenchFeatureStore.archivedRecords)
        applyProjectCatalogProjection(workbenchFeatureStore.projectCatalog)
        if let selectedArchivedRecord {
            _ = workbenchFeatureStore.selectArchivedRecord(selectedArchivedRecord.id, analysisModule: analysisModule)
        } else {
            workbenchFeatureStore.workbenchResultDraft = ""
        }
        inboxFeatureStore.clearPendingState()
    }

    func setupRepositoryProjectionTasks() {
        inboxFeatureStore.setupProjectionTask { [weak self] in
            guard let self else { return }
            syncInboxWorkspaceToPendingImports()
            persistInteractionSnapshotIfReady(source: "inboxProjection")
        }

        workbenchFeatureStore.setupProjectionTasks(
            onArchivedRecordsProjected: { [weak self] records in
                self?.applyArchivedRecordsProjection(records)
            },
            onProjectCatalogProjected: { [weak self] projects in
                self?.applyProjectCatalogProjection(projects)
            }
        )
    }

    func migrateManagedMeasurementPathsToOriginalIfPossible() {
        let fileManager = FileManager.default
        var pendingChanged = false
        var archivedChanged = false

        let migratedPendingImports = inboxFeatureStore.pendingImports.map { pending in
            guard libraryArchiveScan.isManagedMeasurementPath(pending.sourceFilePath),
                  let originalPath = pending.originalFilePath,
                  fileManager.fileExists(atPath: originalPath) else {
                return pending
            }
            var migrated = pending
            migrated.sourceFilePath = URL(fileURLWithPath: originalPath).standardizedFileURL.path
            pendingChanged = true
            return migrated
        }

        let migratedArchivedRecords = workbenchFeatureStore.archivedRecords.map { record in
            var migrated = record
            var didChange = false

            if libraryArchiveScan.isManagedMeasurementPath(record.measurement.sourceFilePath),
               let originalPath = record.measurement.originalFilePath,
               fileManager.fileExists(atPath: originalPath) {
                migrated.measurement.sourceFilePath = URL(fileURLWithPath: originalPath).standardizedFileURL.path
                didChange = true
            }

            if libraryArchiveScan.isManagedMeasurementPath(record.dataset.sourceFilePath),
               let originalPath = record.dataset.originalFilePath ?? record.measurement.originalFilePath,
               fileManager.fileExists(atPath: originalPath) {
                migrated.dataset.sourceFilePath = URL(fileURLWithPath: originalPath).standardizedFileURL.path
                didChange = true
            }

            if didChange {
                archivedChanged = true
            }
            return migrated
        }

        if pendingChanged {
            replacePendingImports(migratedPendingImports)
        }
        if archivedChanged {
            replaceArchivedRecords(migratedArchivedRecords)
        }
    }

    func syncInboxWorkspaceToPendingImports() {
        let prunedWorkspace = inboxFeatureStore.pruneWorkspaceByValidPendingIDs(
            interactionValue(\.inboxWorkspaceByPendingID)
        )
        let sanitizedWorkspace = prunedWorkspace.mapValues { state in
            InboxPendingWorkspaceState.snapshotSafe(
                draft: state.draft,
                editableFileContents: state.editableFileContents,
                hasEditableFileContents: state.hasEditableFileContents,
                routingDraft: nil
            )
        }
        updateInteractionValue(\.inboxWorkspaceByPendingID, to: sanitizedWorkspace, source: "inboxWorkspaceSync")
    }

    func replaceArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord], persist: Bool = true) {
        let updated = workbenchFeatureStore.replaceArchivedRecords(records, persist: persist)
        applyArchivedRecordsProjection(updated)
    }

    private func replacePendingImports(_ imports: [SpinLabDomain.PendingImport], persist: Bool = true) {
        _ = inboxFeatureStore.replacePendingImports(imports, persist: persist)
        syncInboxWorkspaceToPendingImports()
        persistInteractionSnapshotIfReady(source: "replacePendingImports")
    }

    private func applyPendingImportsProjection(_ imports: [SpinLabDomain.PendingImport]) {
        inboxFeatureStore.projectPendingImports(imports)
        syncInboxWorkspaceToPendingImports()
        persistInteractionSnapshotIfReady(source: "applyPendingImportsProjection")
    }

    private func applyArchivedRecordsProjection(_ records: [SpinLabDomain.ArchivedRecord]) {
        workbenchFeatureStore.archivedRecords = records
        if let selectedArchivedRecordID = workbenchFeatureStore.selectedArchivedRecordID,
           !records.contains(where: { $0.id == selectedArchivedRecordID }) {
            workbenchFeatureStore.selectedArchivedRecordID = records.first?.id
        } else if workbenchFeatureStore.selectedArchivedRecordID == nil {
            workbenchFeatureStore.selectedArchivedRecordID = records.first?.id
        }
    }

    private func applyProjectCatalogProjection(_ projects: [SpinLabDomain.Project]) {
        workbenchFeatureStore.projectCatalog = projects
    }
}
