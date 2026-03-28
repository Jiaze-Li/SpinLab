import Foundation
import Observation

@MainActor
@Observable
final class InboxFeatureStore {
    var pendingImports: [SpinLabDomain.PendingImport]
    var selectedPendingImportID: UUID?
    private(set) var routingRuleVersion: Int = 0
    private(set) var routingRuleSourceLabel: String = "unknown"
    private(set) var routingRuleSourcePath: String = "unknown"
    private(set) var routingRuleFingerprint: String = "unknown"

    @ObservationIgnored
    let inboxRoutingState: InboxRoutingState

    @ObservationIgnored
    private let inboxRepository: InboxRepository
    @ObservationIgnored
    private var pendingImportsProjectionTask: Task<Void, Never>?
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
        inboxRoutingState.restoreDrafts(from: workspaceByPendingID)
    }

    func clearPendingState() {
        inboxRoutingState.clearPendingState()
    }

    func clearPendingImports() {
        selectedPendingImportID = nil
        clearPendingState()
        _ = replacePendingImports([])
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
        managedStorage: SpinLabManagedStorage,
        importPipeline: SpinLabImportPipeline,
        excludedOriginalFilePaths: Set<String>
    ) -> [SpinLabDomain.PendingImport] {
        let managedFiles = managedStorage.importMeasurementFiles(
            from: urls,
            allowedFileExtensions: importPipeline.supportedFileExtensions,
            ignoredFileExtensions: importPipeline.ignoredFileExtensions,
            excludedOriginalFilePaths: excludedOriginalFilePaths
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
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        inboxRoutingState.pendingRoutingSnapshot(for: pending)
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        inboxRoutingState.cachedPendingRoutingSnapshot(for: pendingID)
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        inboxRoutingState.matchedExistingLibraryDrawer(sampleInput: sampleInput)
    }

    func pendingRoutePresentation(
        for pending: SpinLabDomain.PendingImport,
        substrateWarning: String?
    ) -> PendingRoutePresentation {
        inboxRoutingState.pendingRoutePresentation(
            for: pending,
            substrateWarning: substrateWarning
        )
    }

    func pendingRoutePresentationByID(
        substrateWarning: (SpinLabDomain.PendingImport) -> String?
    ) -> [UUID: PendingRoutePresentation] {
        inboxRoutingState.pendingRoutePresentationByID(
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
    }

    func confirmPendingImport(
        pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        useCase: ConfirmPendingImportUseCase,
        libraryRepository: LibraryRepository,
        makeArchivedRecord: (SpinLabDomain.PendingImport, PendingImportConfirmationDraft) -> SpinLabDomain.ArchivedRecord
    ) -> Result<ConfirmPendingImportUseCase.Output, AppError> {
        let result = useCase.execute(
            input: ConfirmPendingImportUseCase.Input(
                pending: pending,
                draft: draft
            ),
            inboxRepository: inboxRepository,
            libraryRepository: libraryRepository,
            makeArchivedRecord: makeArchivedRecord
        )

        if case let .success(output) = result {
            projectPendingImports(output.pendingImports)
            clearRoutingData(for: pending.id)
        }
        return result
    }

    @discardableResult
    func refreshRoutingRuleMetadata(forceReload: Bool) -> RuleLoader.LoadResult {
        let loadResult = inboxRoutingState.refreshRoutingRuleMetadata(forceReload: forceReload)
        routingRuleVersion = loadResult.metadata.version
        routingRuleSourceLabel = loadResult.metadata.sourceLabel
        routingRuleSourcePath = loadResult.metadata.sourcePath
        routingRuleFingerprint = loadResult.metadata.fingerprint
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
