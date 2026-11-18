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
        service.createSample(draft: draft(for: sample, batch: batch), rootURL: rootURL, libraryStore: libraryStore, settings: settings)
    }
}
