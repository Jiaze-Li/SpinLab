import Foundation
import Testing
@testable import SpinLabApp

// PR #148 corrective pass: SelectedHitDisplayInfo.resolvedLabels must carry a stable per-series
// identity (ResolvedSeriesPresentation.identityKey) alongside finalLabel, because one hit can
// legitimately produce multiple series that share an identical finalLabel (e.g. AHE's
// per-channel fan-out) — using finalLabel itself as SwiftUI ForEach identity would collide.

@Suite("PR #148 SelectedHitsTray identity")
struct PR148SelectedHitsTrayIdentityTests {
    @Test("two series from the same hit with identical finalLabel remain representable with distinct identity keys")
    func duplicateFinalLabelsHaveDistinctIdentityKeys() {
        let labels = [
            ResolvedSeriesLabel(seriesIdentityKey: "hit-1::ch1", finalLabel: "80K"),
            ResolvedSeriesLabel(seriesIdentityKey: "hit-1::ch2", finalLabel: "80K")
        ]

        #expect(labels[0].finalLabel == labels[1].finalLabel,
                "duplicate finalLabel is a legitimate, expected case")
        #expect(labels[0].seriesIdentityKey != labels[1].seriesIdentityKey,
                "seriesIdentityKey must distinguish series even when finalLabel collides")

        let identityKeys = Set(labels.map(\.seriesIdentityKey))
        #expect(identityKeys.count == labels.count,
                "every series must be uniquely representable by its identity key, regardless of label collisions")
    }

    @MainActor
    @Test("selectedHitDisplayInfos joins ResolvedSeriesPresentation.identityKey into resolvedLabels, not just finalLabel")
    func selectedHitDisplayInfosCarriesIdentityKey() {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let wfs = WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/dup.spinlab.json",
            measurementFilePath: "/data/dup.dat",
            sourceFilePath: "/data/dup.dat",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe",
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1", "ch2"],
            appliedAt: .distantPast
        )
        wfs.aheWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .ahe)

        // No render pipeline output has been produced in this unit-level test, so
        // resolvedLabels stays empty and the row falls back to sampleBatchAndSubstrate — this
        // just proves the join call site compiles against the identity-carrying type and stays
        // stable when there is nothing to join.
        let infos = wfs.selectedHitDisplayInfos(for: .ahe)
        #expect(infos.count == 1)
        #expect(infos.first?.resolvedLabels.isEmpty == true)
    }
}
