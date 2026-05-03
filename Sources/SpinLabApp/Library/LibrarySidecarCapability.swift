import Foundation

protocol LibrarySidecarCapability {
    func loadSidecar(atPath path: String) -> SpinLabFileSidecar?
    func saveConditionOverride(sidecarPath: String, conditionId: String, value: String) -> Bool
    func removeConditionOverride(sidecarPath: String, conditionId: String) -> Bool
    func recomputeAllMeasurementSidecars(rootURL: URL) -> LibraryStore.BackfillSidecarsResult
    func computeStaleCount(rootURL: URL, currentFingerprint: String) -> Int
    func computeRecomputeDiff(rootURL: URL) -> [RecomputeDiffItem]
}

extension LibrarySidecarService: LibrarySidecarCapability {}
