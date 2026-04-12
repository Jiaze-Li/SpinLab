import Foundation

@MainActor
final class InteractionSnapshotCoordinator {
    private let interactionMemory: InteractionMemoryStore

    init(interactionMemory: InteractionMemoryStore) {
        self.interactionMemory = interactionMemory
    }

    func markReady() {
        interactionMemory.markReady()
    }

    func value<Value>(_ keyPath: KeyPath<SpinLabInteractionSnapshot, Value>) -> Value {
        interactionMemory.value(keyPath)
    }

    func updateValue<Value>(_ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>, to value: Value) {
        interactionMemory.updateValue(keyPath, to: value)
    }

    func entryValue<Value>(
        for id: UUID,
        in keyPath: KeyPath<SpinLabInteractionSnapshot, [String: Value]>
    ) -> Value? {
        interactionMemory.entryValue(for: InteractionSnapshotKeyCodec.dictionaryKey(for: id), in: keyPath)
    }

    func updateEntryValue<Value>(
        for id: UUID,
        in keyPath: WritableKeyPath<SpinLabInteractionSnapshot, [String: Value]>,
        value: Value?
    ) {
        interactionMemory.updateEntryValue(
            for: InteractionSnapshotKeyCodec.dictionaryKey(for: id),
            in: keyPath,
            value: value
        )
    }

    func restoreAll(
        selectedAreaSetter: (AppArea) -> Void,
        inboxStore: InboxFeatureStore,
        libraryStore: LibraryFeatureStore,
        workbenchStore: WorkbenchFeatureStore
    ) {
        interactionMemory.restore { snapshot in
            selectedAreaSetter(snapshot.selectedArea)
            libraryStore.restoreInteraction(
                libraryActiveSelectionSource: snapshot.libraryActiveSelectionSource,
                librarySelectedPrefix: snapshot.librarySelectedPrefix,
                librarySelectedBatchId: snapshot.librarySelectedBatchId,
                librarySelectedSampleId: snapshot.librarySelectedSampleId
            )
            inboxStore.restoreInteraction(
                selectedPendingImportID: snapshot.selectedPendingImportID
            )
            workbenchStore.restoreInteraction(
                selectedArchivedRecordID: snapshot.selectedArchivedRecordID,
                workbenchResultDraft: snapshot.workbenchResultDraft,
                threeOmegaGeometryLxx: snapshot.threeOmegaGeometryLxx,
                threeOmegaGeometryLxy: snapshot.threeOmegaGeometryLxy,
                threeOmegaGeometryDNm: snapshot.threeOmegaGeometryDNm,
                threeOmegaV3Method: snapshot.threeOmegaV3Method,
                threeOmegaTitleTemplate: snapshot.threeOmegaTitleTemplate,
                threeOmegaStackOffsetMultiplier: snapshot.threeOmegaStackOffsetMultiplier,
                threeOmegaMinGapFraction: snapshot.threeOmegaMinGapFraction,
                threeOmegaRTSidecarPath: snapshot.threeOmegaRTSidecarPath,
                threeOmegaFitRanges: snapshot.threeOmegaFitRanges,
                threeOmegaPlotLegendPoints: snapshot.threeOmegaPlotLegendPoints,
                aheTitleTemplate: snapshot.aheTitleTemplate,
                xyRotationPhiOffsets: snapshot.xyRotationPhiOffsets,
                xyRotationActiveTab: snapshot.xyRotationActiveTab,
                xyRotationTitleTemplate: snapshot.xyRotationTitleTemplate,
                xyRotationStackOffset: snapshot.xyRotationStackOffset,
                xyRotationCenterBaseline: snapshot.xyRotationCenterBaseline,
                xyRotationLinearDetrend: snapshot.xyRotationLinearDetrend,
                xyRotationPlotLegendPoints: snapshot.xyRotationPlotLegendPoints
            )
            snapshot.inboxWorkspaceByPendingID = inboxStore.pruneWorkspaceByValidPendingIDs(
                snapshot.inboxWorkspaceByPendingID
            )
            inboxStore.restoreRoutingDrafts(from: snapshot.inboxWorkspaceByPendingID)
        }
    }

    func captureAll(
        selectedArea: AppArea,
        inboxStore: InboxFeatureStore,
        libraryStore: LibraryFeatureStore,
        workbenchStore: WorkbenchFeatureStore
    ) {
        interactionMemory.captureIfReady { snapshot in
            snapshot.selectedArea = selectedArea
            libraryStore.captureInteraction(into: &snapshot)
            inboxStore.captureInteraction(into: &snapshot)
            workbenchStore.captureInteraction(into: &snapshot)
        }
    }

    func flushNow() {
        interactionMemory.flushNow()
    }
}
