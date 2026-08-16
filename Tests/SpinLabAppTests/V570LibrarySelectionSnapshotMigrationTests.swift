import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.7.0 Library Selection Snapshot Migration")
struct V570LibrarySelectionSnapshotMigrationTests {

    @Test("legacy browser selection migrates into browser ownership")
    func legacyBrowserSelectionMigratesIntoBrowserOwnership() {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.libraryActiveSelectionSource = .browser

        snapshot.librarySelectedPrefix = "TOP-BROWSER-PREFIX"
        snapshot.librarySelectedBatchId = "TOP-BROWSER-BATCH"
        snapshot.librarySelectedSampleId = "TOP-BROWSER-SAMPLE"
        snapshot.libraryBrowserSelectedPrefix = nil
        snapshot.libraryBrowserSelectedBatchId = nil
        snapshot.libraryBrowserSelectedSampleId = nil

        snapshot.libraryView = LibraryInteractionState(
            selectedPrefix: "VIEW-BROWSER-PREFIX",
            selectedBatchId: "VIEW-BROWSER-BATCH",
            selectedSampleId: "VIEW-BROWSER-SAMPLE"
        )

        let migrated = InteractionSnapshotMigration.migrate(snapshot, from: 1)

        #expect(migrated.libraryBrowserSelectedPrefix == "TOP-BROWSER-PREFIX")
        #expect(migrated.libraryBrowserSelectedBatchId == "TOP-BROWSER-BATCH")
        #expect(migrated.libraryBrowserSelectedSampleId == "TOP-BROWSER-SAMPLE")
        #expect(migrated.librarySelectedPrefix == nil)
        #expect(migrated.librarySelectedBatchId == nil)
        #expect(migrated.librarySelectedSampleId == nil)

        #expect(migrated.libraryView.browserSelectedPrefix == "VIEW-BROWSER-PREFIX")
        #expect(migrated.libraryView.browserSelectedBatchId == "VIEW-BROWSER-BATCH")
        #expect(migrated.libraryView.browserSelectedSampleId == "VIEW-BROWSER-SAMPLE")
        #expect(migrated.libraryView.selectedPrefix == nil)
        #expect(migrated.libraryView.selectedBatchId == nil)
        #expect(migrated.libraryView.selectedSampleId == nil)
    }

    @Test("legacy drawer selection stays drawer-owned and leaves browser unset")
    func legacyDrawerSelectionStaysDrawerOwned() {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.libraryActiveSelectionSource = .drawer

        snapshot.librarySelectedPrefix = "TOP-DRAWER-PREFIX"
        snapshot.librarySelectedBatchId = "TOP-DRAWER-BATCH"
        snapshot.librarySelectedSampleId = "TOP-DRAWER-SAMPLE"
        snapshot.libraryBrowserSelectedPrefix = nil
        snapshot.libraryBrowserSelectedBatchId = nil
        snapshot.libraryBrowserSelectedSampleId = nil

        snapshot.libraryView = LibraryInteractionState(
            selectedPrefix: "VIEW-DRAWER-PREFIX",
            selectedBatchId: "VIEW-DRAWER-BATCH",
            selectedSampleId: "VIEW-DRAWER-SAMPLE"
        )

        let migrated = InteractionSnapshotMigration.migrate(snapshot, from: 0)

        #expect(migrated.librarySelectedPrefix == "TOP-DRAWER-PREFIX")
        #expect(migrated.librarySelectedBatchId == "TOP-DRAWER-BATCH")
        #expect(migrated.librarySelectedSampleId == "TOP-DRAWER-SAMPLE")
        #expect(migrated.libraryBrowserSelectedPrefix == nil)
        #expect(migrated.libraryBrowserSelectedBatchId == nil)
        #expect(migrated.libraryBrowserSelectedSampleId == nil)

        #expect(migrated.libraryView.selectedPrefix == "VIEW-DRAWER-PREFIX")
        #expect(migrated.libraryView.selectedBatchId == "VIEW-DRAWER-BATCH")
        #expect(migrated.libraryView.selectedSampleId == "VIEW-DRAWER-SAMPLE")
        #expect(migrated.libraryView.browserSelectedPrefix == nil)
        #expect(migrated.libraryView.browserSelectedBatchId == nil)
        #expect(migrated.libraryView.browserSelectedSampleId == nil)
    }

    @Test("schema v2 snapshot preserves both independent selection triples exactly")
    func schemaV2PreservesIndependentTriples() {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.libraryActiveSelectionSource = .browser

        snapshot.librarySelectedPrefix = "DRAWER-PREFIX"
        snapshot.librarySelectedBatchId = "DRAWER-BATCH"
        snapshot.librarySelectedSampleId = "DRAWER-SAMPLE"
        snapshot.libraryBrowserSelectedPrefix = "BROWSER-PREFIX"
        snapshot.libraryBrowserSelectedBatchId = "BROWSER-BATCH"
        snapshot.libraryBrowserSelectedSampleId = "BROWSER-SAMPLE"

        snapshot.libraryView = LibraryInteractionState(
            selectedPrefix: "VIEW-DRAWER-PREFIX",
            selectedBatchId: "VIEW-DRAWER-BATCH",
            selectedSampleId: "VIEW-DRAWER-SAMPLE",
            browserSelectedPrefix: "VIEW-BROWSER-PREFIX",
            browserSelectedBatchId: "VIEW-BROWSER-BATCH",
            browserSelectedSampleId: "VIEW-BROWSER-SAMPLE"
        )

        let migrated = InteractionSnapshotMigration.migrate(snapshot, from: 2)

        #expect(migrated == snapshot)
    }
}
