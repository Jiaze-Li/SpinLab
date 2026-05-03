import Foundation
import Observation

struct ImportProgressState {
    var isRunning: Bool = false
    var totalCount: Int = 0
    var processedCount: Int = 0
    var currentFileName: String = ""
    var failedCount: Int = 0
}

@MainActor
@Observable
final class InboxFeatureStore {
    var pendingImports: [SpinLabDomain.PendingImport]
    var selectedPendingImportID: UUID?
    private(set) var routingRuleVersion: Int = 0
    private(set) var routingRuleSourceLabel: String = "unknown"
    private(set) var routingRuleSourcePath: String = "unknown"
    private(set) var routingRuleFingerprint: String = "unknown"
    private(set) var routingRuleHashPrefix: String = "unknown"
    private(set) var routingSnapshotRevision: Int = 0
    var importProgressState: ImportProgressState = .init()

    @ObservationIgnored
    let inboxRoutingState: InboxRoutingState

    @ObservationIgnored
    private let inboxRepository: InboxRepository
    @ObservationIgnored
    private var pendingImportsProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var importTask: Task<Void, Never>?
    @ObservationIgnored
    private var bufferedPendingImportsProjection: [SpinLabDomain.PendingImport]?
    @ObservationIgnored
    private var isPendingImportsProjectionDrainScheduled = false

    init(
        inboxRepository: InboxRepository,
        routingCapabilities: RoutingCapabilities,
        ruleRuntime: any RuleRuntimeCapability
    ) {
        self.inboxRepository = inboxRepository
        self.pendingImports = inboxRepository.pendingImports
        self.selectedPendingImportID = inboxRepository.pendingImports.first?.id
        self.inboxRoutingState = InboxRoutingState(
            routingCapabilities: routingCapabilities,
            ruleRuntime: ruleRuntime
        )
    }

    deinit {
        pendingImportsProjectionTask?.cancel()
        importTask?.cancel()
    }

    func restoreInteraction(selectedPendingImportID: UUID?) {
        if let selectedPendingImportID,
           pendingImports.contains(where: { $0.id == selectedPendingImportID }) {
            self.selectedPendingImportID = selectedPendingImportID
        }
    }

    func captureInteraction(into snapshot: inout SpinLabInteractionSnapshot) {
        snapshot.selectedPendingImportID = selectedPendingImportID
    }

    func pruneWorkspaceByValidPendingIDs(
        _ workspaceByPendingID: [String: InboxPendingWorkspaceState]
    ) -> [String: InboxPendingWorkspaceState] {
        let validPendingIDs = Set(pendingImports.map { InteractionSnapshotKeyCodec.dictionaryKey(for: $0.id) })
        return workspaceByPendingID.filter { key, _ in
            validPendingIDs.contains(key)
        }
    }

    func restoreRoutingDrafts(from workspaceByPendingID: [String: InboxPendingWorkspaceState]) {
        // Routing matching must not be driven by persisted interaction snapshot drafts.
        // Keep runtime routing drafts empty on restore so matching only uses current sample text.
        _ = workspaceByPendingID
        inboxRoutingState.restoreDrafts(from: [:])
    }

    func clearPendingState() {
        inboxRoutingState.clearPendingState()
    }

    func clearPendingImports() {
        selectedPendingImportID = nil
        clearPendingState()
        _ = replacePendingImports([])
    }

    @discardableResult
    func removeSelectedPendingImport() -> UUID? {
        guard let selectedID = selectedPendingImportID else {
            return nil
        }
        let updated = inboxRepository.performTransaction { pendingImports in
            pendingImports.removeAll { $0.id == selectedID }
        }
        applyPendingImportsProjection(updated)
        clearRoutingData(for: selectedID)
        return selectedID
    }

    func clearRoutingData(for pendingID: UUID) {
        inboxRoutingState.clearRoutingData(for: pendingID)
    }

    func replacePendingImports(_ imports: [SpinLabDomain.PendingImport], persist: Bool = true) -> [SpinLabDomain.PendingImport] {
        let updated = inboxRepository.replacePendingImports(imports, persist: persist)
        applyPendingImportsProjection(updated)
        return updated
    }

    func importFiles(
        from urls: [URL],
        inboxImportFilter: InboxImportFilterService,
        importPipeline: SpinLabImportPipeline,
        excludedOriginalFilePaths: Set<String>,
        excludedContentFingerprints: Set<String>
    ) -> [SpinLabDomain.PendingImport] {
        let managedFiles = inboxImportFilter.importMeasurementFiles(
            from: urls,
            allowedFileExtensions: importPipeline.supportedFileExtensions,
            ignoredFileExtensions: importPipeline.ignoredFileExtensions,
            excludedOriginalFilePaths: excludedOriginalFilePaths,
            excludedContentFingerprints: excludedContentFingerprints
        )
        let imported = importPipeline.importFiles(managedFiles)
        guard !imported.isEmpty else {
            return []
        }

        var nextPendingImports = pendingImports
        nextPendingImports.insert(contentsOf: imported, at: 0)
        refreshPendingDrawerMatches(for: imported.map(\.id))
        _ = replacePendingImports(nextPendingImports)
        selectedPendingImportID = imported.first?.id
        return imported
    }

    func startImportFiles(
        from urls: [URL],
        inboxImportFilter: InboxImportFilterService,
        importPipeline: SpinLabImportPipeline,
        excludedOriginalFilePaths: Set<String>,
        excludedContentFingerprints: Set<String>,
        excludedFileNames: Set<String>,
        onCompleted: @escaping @MainActor ([SpinLabDomain.PendingImport]) -> Void
    ) {
        importTask?.cancel()

        // Phase 1 (sync): fast scan (path/file-name dedupe only) and initialize progress immediately.
        let scannedURLs = inboxImportFilter.scanMeasurementSourceFiles(
            from: urls,
            allowedFileExtensions: importPipeline.supportedFileExtensions,
            ignoredFileExtensions: importPipeline.ignoredFileExtensions,
            excludedOriginalFilePaths: excludedOriginalFilePaths,
            excludedFileNames: excludedFileNames
        )
        guard !scannedURLs.isEmpty else {
            return
        }

        importProgressState = ImportProgressState(
            isRunning: true,
            totalCount: scannedURLs.count,
            processedCount: 0,
            currentFileName: scannedURLs[0].lastPathComponent,
            failedCount: 0
        )

        // Phase 2 (async): fingerprint on detached utility task, then parse one file at a time.
        importTask = Task { @MainActor [weak self] in
            defer { self?.importProgressState = .init() }

            var accumulated: [SpinLabDomain.PendingImport] = []
            accumulated.reserveCapacity(scannedURLs.count)
            var seenContentFingerprints = Set(excludedContentFingerprints.map { $0.lowercased() })

            for url in scannedURLs {
                guard !Task.isCancelled, let self else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                self.importProgressState.currentFileName = url.lastPathComponent

                let fingerprint = await Task.detached(priority: .utility) {
                    inboxImportFilter.contentFingerprint(for: url)
                }.value
                guard !Task.isCancelled else { return }

                if let fingerprint {
                    let normalizedFingerprint = fingerprint.lowercased()
                    let inserted = seenContentFingerprints.insert(normalizedFingerprint).inserted
                    if !inserted {
                        self.importProgressState.processedCount += 1
                        continue
                    }
                }

                let file = ImportedMeasurementFile(
                    fileName: url.lastPathComponent,
                    sourceFileURL: url,
                    originalFileURL: url
                )

                let parsed = importPipeline.importFiles([file])
                if parsed.isEmpty {
                    self.importProgressState.failedCount += 1
                } else {
                    accumulated.append(contentsOf: parsed)
                }
                self.importProgressState.processedCount += 1
            }

            guard !Task.isCancelled, let self, !accumulated.isEmpty else { return }

            var next = self.pendingImports
            next.insert(contentsOf: accumulated, at: 0)
            self.refreshPendingDrawerMatches(for: accumulated.map(\.id))
            _ = self.replacePendingImports(next)
            self.selectedPendingImportID = accumulated.first?.id
            onCompleted(accumulated)
        }
    }

    func recomputeSpecificPendingHints(
        pendingIDs: Set<UUID>,
        recomputeParsedHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints
    ) -> [SpinLabDomain.PendingImport] {
        let updated = pendingImports.map { pending -> SpinLabDomain.PendingImport in
            guard pendingIDs.contains(pending.id) else { return pending }
            var next = pending
            next.parsedHints = recomputeParsedHints(pending)
            return next
        }
        _ = replacePendingImports(updated)
        refreshPendingDrawerMatches(for: Array(pendingIDs))
        return updated
    }

    func recomputeAllPendingParsedHints(
        recomputeParsedHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints
    ) -> [SpinLabDomain.PendingImport] {
        let recomputedPendingImports = pendingImports.map { pending in
            var next = pending
            next.parsedHints = recomputeParsedHints(pending)
            return next
        }
        clearPendingState()
        _ = replacePendingImports(recomputedPendingImports)
        refreshPendingDrawerMatches()
        return recomputedPendingImports
    }

    func projectPendingImports(_ imports: [SpinLabDomain.PendingImport]) {
        applyPendingImportsProjection(imports)
    }

    func setupProjectionTask(onProjected: @escaping @MainActor () -> Void) {
        pendingImportsProjectionTask?.cancel()
        pendingImportsProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await imports in inboxRepository.pendingImportsStream {
                await MainActor.run {
                    self.bufferedPendingImportsProjection = imports
                    self.schedulePendingImportsProjectionDrainIfNeeded(onProjected: onProjected)
                }
            }
        }
    }

    func refreshPendingDrawerMatches(for pendingIDs: [UUID]? = nil) {
        inboxRoutingState.refreshPendingDrawerMatches(
            pendingImports: pendingImports,
            for: pendingIDs
        )
        routingSnapshotRevision &+= 1
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        inboxRoutingState.pendingRoutingSnapshot(for: pending)
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        _ = routingSnapshotRevision
        return inboxRoutingState.cachedPendingRoutingSnapshot(for: pendingID)
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        inboxRoutingState.matchedExistingLibraryDrawer(sampleInput: sampleInput)
    }

    func pendingRoutePresentation(
        for pending: SpinLabDomain.PendingImport,
        substrateWarning: String?
    ) -> PendingRoutePresentation {
        _ = routingSnapshotRevision
        return inboxRoutingState.pendingRoutePresentation(
            for: pending,
            substrateWarning: substrateWarning
        )
    }

    func pendingRoutePresentationByID(
        substrateWarning: (SpinLabDomain.PendingImport) -> String?
    ) -> [UUID: PendingRoutePresentation] {
        _ = routingSnapshotRevision
        return inboxRoutingState.pendingRoutePresentationByID(
            pendingImports: pendingImports,
            substrateWarning: substrateWarning
        )
    }

    func pendingRoutePlan(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RoutePlan {
        inboxRoutingState.pendingRoutePlan(for: pending)
    }

    func pendingRouteStatus(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RouteStatus {
        inboxRoutingState.pendingRouteStatus(for: pending)
    }

    func hasSavedRoutingDraft(for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxRoutingState.hasSavedRoutingDraft(for: pending)
    }

    func routingDraft(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxRoutingState.routingDraft(for: pending)
    }

    func routingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxRoutingState.routingDraftBaseline(for: pending)
    }

    func isRoutingDraftDirty(_ draft: PendingRoutingDraft, for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxRoutingState.isRoutingDraftDirty(draft, for: pending)
    }

    func saveRoutingDraft(_ draft: PendingRoutingDraft, for pendingID: UUID) {
        inboxRoutingState.saveRoutingDraft(
            draft,
            for: pendingID,
            pendingImports: pendingImports
        )
        routingSnapshotRevision &+= 1
    }

    func applyPending(processedIDs: [UUID]) {
        guard !processedIDs.isEmpty else {
            return
        }

        let processedSet = Set(processedIDs)
        let updated = inboxRepository.performTransaction { pendingImports in
            pendingImports.removeAll { processedSet.contains($0.id) }
        }
        applyPendingImportsProjection(updated)
        for pendingID in processedSet {
            clearRoutingData(for: pendingID)
        }
    }

    @discardableResult
    func refreshRoutingRuleMetadata(forceReload: Bool) -> RuleLoader.LoadResult {
        let loadResult = inboxRoutingState.refreshRoutingRuleMetadata(forceReload: forceReload)
        routingRuleVersion = loadResult.metadata.schemaVersion
        routingRuleSourceLabel = loadResult.metadata.sourceLabel
        routingRuleSourcePath = loadResult.metadata.sourcePath
        routingRuleFingerprint = loadResult.metadata.fingerprint
        routingRuleHashPrefix = loadResult.metadata.contentHashPrefix8
        return loadResult
    }

    func rebuildDrawerMatchCandidates(from samples: [LibrarySample]) {
        inboxRoutingState.rebuildDrawerMatchCandidates(from: samples)
    }

    func clearDrawerMatchCandidates() {
        inboxRoutingState.clearDrawerMatchCandidates()
    }

    private func applyPendingImportsProjection(_ imports: [SpinLabDomain.PendingImport]) {
        pendingImports = imports
        if let selectedPendingImportID,
           !imports.contains(where: { $0.id == selectedPendingImportID }) {
            self.selectedPendingImportID = imports.first?.id
        } else if selectedPendingImportID == nil {
            selectedPendingImportID = imports.first?.id
        }
    }

    @MainActor
    private func schedulePendingImportsProjectionDrainIfNeeded(onProjected: @escaping @MainActor () -> Void) {
        scheduleProjectionDrainIfNeeded(
            scheduledFlag: \.isPendingImportsProjectionDrainScheduled,
            bufferedValue: \.bufferedPendingImportsProjection,
            apply: { [weak self] imports in
                guard let self else { return }
                self.applyPendingImportsProjection(imports)
                onProjected()
            }
        )
    }

    @MainActor
    private func scheduleProjectionDrainIfNeeded<T>(
        scheduledFlag: ReferenceWritableKeyPath<InboxFeatureStore, Bool>,
        bufferedValue: ReferenceWritableKeyPath<InboxFeatureStore, T?>,
        apply: @escaping @MainActor (T) -> Void
    ) {
        guard !self[keyPath: scheduledFlag] else {
            return
        }
        self[keyPath: scheduledFlag] = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let value = self[keyPath: bufferedValue] {
                apply(value)
                self[keyPath: bufferedValue] = nil
            }
            self[keyPath: scheduledFlag] = false
        }
    }
}
