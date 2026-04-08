import Foundation

// Layer boundary:
// App state talks to routing only through this state/service and capability contracts.
// Routing internals (parse/route/match/evaluate/rules) stay behind this boundary.
final class InboxRoutingState {
    private let routingCapabilities: RoutingCapabilities
    private let ruleRuntime: any RuleRuntimeCapability
    private let sampleKeyNormalizer = SampleKeyNormalizer()
    private let pendingRoutePresentationBuilder = PendingRoutePresentationBuilder()

    private var pendingRoutingSnapshotByID: [UUID: SpinLabDomain.PendingRoutingSnapshot] = [:]
    private var pendingRoutingDraftsByID: [UUID: PendingRoutingDraft] = [:]
    private var drawerMatchIndex = DrawerMatchIndex()
    private var drawerMatchSamples: [LibrarySample] = []
    private var drawerMatchRuleFingerprint: String = "unknown"
    private var routingRuleFingerprint: String = "unknown"

    var nameExistsInLibraryDrawer: (_ fileName: String, _ matchedSampleID: String, _ workflowID: String?) -> Bool = { _, _, _ in false }

    init(
        routingCapabilities: RoutingCapabilities,
        ruleRuntime: any RuleRuntimeCapability
    ) {
        self.routingCapabilities = routingCapabilities
        self.ruleRuntime = ruleRuntime
    }

    func restoreDrafts(from workspaceByPendingID: [String: InboxPendingWorkspaceState]) {
        pendingRoutingDraftsByID = workspaceByPendingID.reduce(into: [:]) { partial, entry in
            guard let uuid = UUID(uuidString: entry.key),
                  let routingDraft = entry.value.routingDraft else {
                return
            }
            partial[uuid] = routingDraft
        }
    }

    func clearPendingState() {
        pendingRoutingDraftsByID = [:]
        pendingRoutingSnapshotByID = [:]
    }

    func clearRoutingData(for pendingID: UUID) {
        pendingRoutingDraftsByID[pendingID] = nil
        pendingRoutingSnapshotByID[pendingID] = nil
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        pendingRoutingSnapshotByID[pendingID]
    }

    func hasSavedRoutingDraft(for pending: SpinLabDomain.PendingImport) -> Bool {
        pendingRoutingDraftsByID[pending.id] != nil
    }

    func routingDraft(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        if let saved = pendingRoutingDraftsByID[pending.id] {
            return saved
        }
        return routingDraftBaseline(for: pending)
    }

    func routingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        makeRoutingDraftBaseline(for: pending)
    }

    func isRoutingDraftDirty(_ draft: PendingRoutingDraft, for pending: SpinLabDomain.PendingImport) -> Bool {
        let trimmedCurrent = PendingRoutingDraft(
            defaultSampleKey: draft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines),
            channelSampleKeyOverrides: draft.channelSampleKeyOverrides.mapValues {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        return trimmedCurrent != routingDraft(for: pending)
    }

    func saveRoutingDraft(
        _ draft: PendingRoutingDraft,
        for pendingID: UUID,
        pendingImports: [SpinLabDomain.PendingImport]
    ) {
        pendingRoutingDraftsByID[pendingID] = PendingRoutingDraft(
            defaultSampleKey: draft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines),
            channelSampleKeyOverrides: draft.channelSampleKeyOverrides.mapValues {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        refreshPendingDrawerMatches(pendingImports: pendingImports, for: [pendingID])
    }

    func pendingRoutePlan(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RoutePlan {
        pendingRoutingSnapshot(for: pending).routePlan
    }

    func pendingRouteStatus(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RouteStatus {
        pendingRoutingSnapshot(for: pending).verdict
    }

    func pendingRoutePresentation(
        for pending: SpinLabDomain.PendingImport,
        substrateWarning: String?
    ) -> PendingRoutePresentation {
        let routingSnapshot = pendingRoutingSnapshot(for: pending)
        return pendingRoutePresentationBuilder.build(
            pending: pending,
            routingSnapshot: routingSnapshot,
            substrateWarning: substrateWarning
        )
    }

    func pendingRoutePresentationByID(
        pendingImports: [SpinLabDomain.PendingImport],
        substrateWarning: (SpinLabDomain.PendingImport) -> String?
    ) -> [UUID: PendingRoutePresentation] {
        Dictionary(uniqueKeysWithValues: pendingImports.map { pending in
            (pending.id, pendingRoutePresentation(for: pending, substrateWarning: substrateWarning(pending)))
        })
    }

    func refreshPendingDrawerMatches(
        pendingImports: [SpinLabDomain.PendingImport],
        for pendingIDs: [UUID]? = nil
    ) {
        let pendingByID = Dictionary(uniqueKeysWithValues: pendingImports.map { ($0.id, $0) })
        let targetIDs = pendingIDs ?? pendingImports.map(\.id)
        guard !targetIDs.isEmpty else {
            pendingRoutingSnapshotByID = [:]
            return
        }

        let validIDs = Set(pendingImports.map(\.id))
        var next = pendingRoutingSnapshotByID.filter { validIDs.contains($0.key) }
        for pendingID in targetIDs {
            guard let pending = pendingByID[pendingID] else {
                next.removeValue(forKey: pendingID)
                continue
            }
            next[pendingID] = evaluatePendingRoutingSnapshot(for: pending)
        }
        pendingRoutingSnapshotByID = next
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        if let cached = pendingRoutingSnapshotByID[pending.id] {
            return cached
        }
        return evaluatePendingRoutingSnapshot(for: pending)
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        ensureDrawerMatchIndexUsesCurrentRules()
        return routingCapabilities.matcher.match(sampleInput: sampleInput, index: drawerMatchIndex)
    }

    func rebuildDrawerMatchCandidates(from samples: [LibrarySample]) {
        drawerMatchSamples = samples
        drawerMatchIndex = routingCapabilities.matcher.makeIndex(from: samples)
        drawerMatchRuleFingerprint = ruleRuntime.loadRulesCached().metadata.fingerprint
    }

    func clearDrawerMatchCandidates() {
        drawerMatchSamples = []
        drawerMatchIndex = DrawerMatchIndex()
        drawerMatchRuleFingerprint = ruleRuntime.loadRulesCached().metadata.fingerprint
    }

    @discardableResult
    func refreshRoutingRuleMetadata(forceReload: Bool) -> RuleLoader.LoadResult {
        let loadResult = forceReload ? ruleRuntime.reloadRulesCached() : ruleRuntime.loadRulesCached()
        let previous = routingRuleFingerprint
        routingRuleFingerprint = loadResult.metadata.fingerprint
        if previous != routingRuleFingerprint {
            ensureDrawerMatchIndexUsesCurrentRules()
        }
        return loadResult
    }

    func currentRoutingRuleFingerprint() -> String {
        routingRuleFingerprint
    }

    private func ensureDrawerMatchIndexUsesCurrentRules() {
        let current = ruleRuntime.loadRulesCached().metadata.fingerprint
        guard drawerMatchRuleFingerprint != current else {
            return
        }
        drawerMatchIndex = routingCapabilities.matcher.makeIndex(from: drawerMatchSamples)
        drawerMatchRuleFingerprint = current
    }

    private func evaluatePendingRoutingSnapshot(
        for pending: SpinLabDomain.PendingImport
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        let parsed = parsedHintsApplyingRoutingDraft(for: pending)
        let routePlan = routingCapabilities.planner.makeRoutePlan(from: parsed)
        var snapshot = routingCapabilities.evaluator.makeSnapshot(
            routePlan: routePlan,
            matchDrawer: { [weak self] sampleInput in
                self?.matchedExistingLibraryDrawer(sampleInput: sampleInput)
            }
        )
        snapshot.nameConflictWarning = resolveNameConflictWarning(
            fileName: pending.fileName,
            scopes: snapshot.scopes,
            workflowID: parsed.workflowID
        )
        return snapshot
    }

    private func resolveNameConflictWarning(
        fileName: String,
        scopes: [SpinLabDomain.RoutingScopeEvaluation],
        workflowID: String?
    ) -> String? {
        for scope in scopes {
            guard let matchedDrawer = scope.matchedDrawer else { continue }
            if nameExistsInLibraryDrawer(fileName, matchedDrawer, workflowID) {
                return RoutingExplanationBook.nameConflictInLibrary().message
            }
        }
        return nil
    }

    private func parsedHintsApplyingRoutingDraft(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints {
        guard let draft = pendingRoutingDraftsByID[pending.id] else {
            return pending.parsedHints
        }

        var parsed = pending.parsedHints
        let trimmedDefault = draft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.defaultSampleKey = trimmedDefault.isEmpty ? nil : normalizedSampleInput(
            trimmedDefault,
            fallbackBatchID: pending.parsedHints.sampleIDs.first,
            fallbackSampleTags: pending.parsedHints.substrateTags
        )

        var channelHints = parsed.channelHints
        for index in channelHints.indices {
            let channelID = channelHints[index].channel
            guard let override = draft.channelSampleKeyOverrides[channelID] else {
                continue
            }
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            channelHints[index].sampleID = trimmed.isEmpty ? nil : normalizedSampleInput(
                trimmed,
                fallbackBatchID: pending.parsedHints.sampleIDs.first,
                fallbackSampleTags: channelHints[index].tags
            )
        }
        parsed.channelHints = channelHints
        return parsed
    }

    private func makeRoutingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        let parsed = pending.parsedHints
        let plan = routingCapabilities.planner.makeRoutePlan(from: parsed)
        let resolutionsByChannel = Dictionary(uniqueKeysWithValues: plan.channelResolutions.map { ($0.channel, $0) })

        var overrides: [String: String] = [:]
        for channel in parsed.channelHints {
            let explicitInput = normalized(channel.sampleID)
            guard explicitInput != nil else {
                overrides[channel.channel] = ""
                continue
            }
            overrides[channel.channel] = resolutionsByChannel[channel.channel]?.sampleId ?? explicitInput ?? ""
        }

        let defaultSampleKey = plan.channelResolutions
            .first(where: { $0.channel == "file" })?
            .sampleId
            ?? parsed.defaultSampleKey
            ?? ""

        return PendingRoutingDraft(
            defaultSampleKey: defaultSampleKey,
            channelSampleKeyOverrides: overrides
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedSampleInput(
        _ value: String,
        fallbackBatchID: String?,
        fallbackSampleTags: [String]
    ) -> String {
        sampleKeyNormalizer.canonicalOrOriginal(
            from: value,
            fallbackBatchID: fallbackBatchID,
            fallbackSampleTags: fallbackSampleTags
        )
    }
}
