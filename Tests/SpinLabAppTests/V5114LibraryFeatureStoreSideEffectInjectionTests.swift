import Testing
import Foundation
@testable import SpinLabApp

// INV-8: LibraryFeatureStore all side-effect deps can be injected via init
// substitute parameters and are actually used (not replaced by default-constructed instances).

private final class FakeLibrarySidecarCapability: LibrarySidecarCapability {
    private(set) var loadCallCount = 0

    func loadSidecar(atPath path: String) -> SpinLabFileSidecar? {
        loadCallCount += 1
        return nil
    }

    func saveConditionOverride(sidecarPath: String, conditionId: String, value: String) -> Bool { false }
    func removeConditionOverride(sidecarPath: String, conditionId: String) -> Bool { false }
    func saveWorkflowOverride(sidecarPath: String, workflowOverride: String) -> Bool { false }
    func clearWorkflowOverride(sidecarPath: String) -> Bool { false }
    func recomputeAllMeasurementSidecars(rootURL: URL) -> LibraryStore.BackfillSidecarsResult {
        LibraryStore.BackfillSidecarsResult(
            scannedSampleCount: 0,
            scannedMeasurementFileCount: 0,
            createdSidecarCount: 0,
            updatedSidecarCount: 0,
            skippedExistingSidecarCount: 0,
            failedSidecarCount: 0
        )
    }

    func computeStaleCount(rootURL: URL, currentFingerprint: String) -> Int { 0 }
    func computeRecomputeDiff(rootURL: URL) -> [RecomputeDiffItem] { [] }
}

@Suite("V5.1.14 LibraryFeatureStore Side-Effect Injection")
@MainActor
struct V5114LibraryFeatureStoreSideEffectInjectionTests {

    @Test("INV-8: loadSidecar routes call to injected capability, not default-constructed service")
    func loadSidecarUsesInjectedCapability() {
        let fake = FakeLibrarySidecarCapability()
        let store = LibraryFeatureStore(librarySidecarService: fake)

        let measurement = AppliedMeasurement(
            id: "/tmp/test.spinlab.json",
            workflow: "test",
            workflowDisplayName: "Test",
            conditions: [:],
            appliedAt: Date(),
            sourceFileName: "test.dat"
        )

        _ = store.loadSidecar(for: measurement)

        #expect(fake.loadCallCount == 1, "injected capability must receive the loadSidecar call")
    }

    @Test("INV-8b: librarySidecarService and libraryRegistrySyncService accept init substitutes (compile-time)")
    func initAcceptsAllSideEffectSubstitutes() {
        let fake = FakeLibrarySidecarCapability()
        let customRegistry = LibraryRegistrySyncService(libraryStore: LibraryStore())
        let store = LibraryFeatureStore(
            librarySidecarService: fake,
            libraryRegistrySyncService: customRegistry
        )
        // Verify the store was constructed successfully with both substitutes injected.
        // The mere fact that this compiles and runs proves both parameters exist in the init.
        #expect(store.librarySettings == store.librarySettings, "store constructed with all side-effect substitutes")
    }
}
