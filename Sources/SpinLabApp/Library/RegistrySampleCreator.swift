import Foundation

/// Adapts a parsed Registry row to the one creation entry (`NativeSampleCreationService.createSample`).
/// The Registry only supplies the input; identity (`smp_`) is issued by `SampleIDIssuer`, and the old
/// Sample Key is recorded as `legacySampleKey`.
struct RegistrySampleCreator {
    let libraryStore: LibraryStore
    let settings: LibrarySettings
    var service = NativeSampleCreationService()

    func draft(for sample: LibrarySample, batch: LibraryBatch) -> CreateNativeSampleDraft {
        var draft = CreateNativeSampleDraft(batchId: sample.batchId)
        draft.substrateDescription = sample.substrateRaw
        draft.displayName = sample.displayName
        draft.metadata = sample.metadata
        draft.numericTags = sample.numericTags
        draft.numericDisplay = sample.numericDisplay
        draft.sampleUID = SampleIDIssuer.issueForNewSample()
        draft.legacySampleKey = sample.legacySampleKey ?? sample.id
        draft.origin = "registry"
        draft.sourceSheetName = sample.sourceSheetName
        draft.sourceRowNumber = sample.sourceRowNumber
        draft.registrySample = sample
        draft.registryBatch = batch
        return draft
    }

    func create(_ sample: LibrarySample, batch: LibraryBatch, rootURL: URL) -> CreateNativeSampleOutcome {
        // Idempotence: the UID is random per call, so a retried or stale-baseline sync must be stopped here.
        // Re-check the Registry key against the index as it is on disk right now; if it already exists, reuse it.
        // An unreadable index falls through: the creation entry fails closed on its own.
        if let current = try? libraryStore.readOnlyCompleteIndex(rootURL: rootURL),
           let existing = SampleLegacyKeyMapping.findRegistryMatch(forIncomingCue: sample.legacySampleKey ?? sample.id, batchId: sample.batchId, in: current) {
            let existingBatch = current.batches.first { $0.id == existing.batchId } ?? batch
            return .success(sample: existing, batch: existingBatch, syncedIndex: current)
        }
        return service.createSample(draft: draft(for: sample, batch: batch), rootURL: rootURL, libraryStore: libraryStore, settings: settings)
    }
}
