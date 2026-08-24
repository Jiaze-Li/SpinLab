import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5C: `LibraryFeatureStore`'s transient Existing field edit state
/// (spec §5/§10/§15). Never exercises real I/O — builds a hand-constructed
/// plan carrying `existingDifferences` directly, same pattern as
/// `V5RegistryGrowthImportOrchestrationTests`.
@Suite("V5.7.2 LibraryFeatureStore Existing field edit state")
@MainActor
struct V572RegistryGrowthExistingEditStateTests {
    private func existingItem(
        batchId: String, sheet: String = "LNO", row: Int = 2,
        differences: [RegistryGrowthExistingDifference]
    ) -> RegistryGrowthImportItem {
        RegistryGrowthImportItem(
            batchId: batchId, sourceNotePaths: ["\(batchId).md"], targetSheetHint: sheet,
            action: .skipExisting(targetSheet: sheet, rowNumber: row),
            columnValues: [:], provenance: [], blankColumns: [], expectedSampleKeys: [],
            warnings: [], existingDifferences: differences, blockingReasons: []
        )
    }

    private func makePlan(items: [RegistryGrowthImportItem]) -> RegistryGrowthImportPlan {
        RegistryGrowthImportPlan(
            registryFingerprint: "fp-1", registrySourcePath: "/tmp/registry.xlsx", builtAt: .now,
            items: items, diagnostics: [], existingCount: 0
        )
    }

    private let dateDiff = RegistryGrowthExistingDifference(field: .date, header: "日期", registryValue: "2026.1.10", obsidianValue: "2026.1.12")
    private let pulseDiff = RegistryGrowthExistingDifference(field: .pulseCount, header: "预打/生长次数", registryValue: "200/3000", obsidianValue: "500/2400")

    // MARK: - A. Final defaults to Registry value → no pending edit

    @Test("A. Final defaults to the Registry value; opening an item creates zero pending edits")
    func finalDefaultsToRegistryValue() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])

        #expect(store.finalValueForRegistryGrowthImportExistingField(batchId: "LNO12", diff: dateDiff) == "2026.1.10")
        #expect(store.registryGrowthImportExistingFieldEdits.isEmpty)
        #expect(store.registryGrowthImportApplyCount == 0)
    }

    // MARK: - B. Use Obsidian → pending edit

    @Test("B. Use Obsidian records a pending edit and becomes actionable")
    func useObsidianRecordsPendingEdit() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])

        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")

        #expect(store.finalValueForRegistryGrowthImportExistingField(batchId: "LNO12", diff: dateDiff) == "2026.1.12")
        #expect(store.registryGrowthImportApplyCount == 1)
    }

    // MARK: - C. Use Registry / Reset → pending edit removed

    @Test("C. Use Registry / Reset removes the pending edit")
    func useRegistryResetsEdit() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")
        #expect(store.registryGrowthImportApplyCount == 1)

        store.resetRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")

        #expect(store.finalValueForRegistryGrowthImportExistingField(batchId: "LNO12", diff: dateDiff) == "2026.1.10")
        #expect(store.registryGrowthImportApplyCount == 0)
        #expect(store.registryGrowthImportExistingFieldEdits["LNO12"] == nil, "the per-batch dictionary entry must be removed entirely once empty, not left as an empty dict")
    }

    // MARK: - D. Custom non-empty value → pending edit; empty Final is ignored

    @Test("D. A custom non-empty Final value records a pending edit")
    func customValueRecordsPendingEdit() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])

        store.setRegistryGrowthImportExistingFieldFinal(batchId: "LNO12", header: "日期", finalValue: "2026.1.15")

        #expect(store.finalValueForRegistryGrowthImportExistingField(batchId: "LNO12", diff: dateDiff) == "2026.1.15")
        #expect(store.registryGrowthImportApplyCount == 1)
    }

    @Test("D2. An empty/whitespace-only Final value is ignored, never recorded as a silent clear")
    func emptyFinalValueIsIgnored() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")

        store.setRegistryGrowthImportExistingFieldFinal(batchId: "LNO12", header: "日期", finalValue: "   ")

        // The prior pending edit (Obsidian value) must survive an ignored
        // empty submission, not be silently cleared.
        #expect(store.finalValueForRegistryGrowthImportExistingField(batchId: "LNO12", diff: dateDiff) == "2026.1.12")
    }

    // MARK: - E/F. Apply count is per-BATCH, not per-field

    @Test("E. Two edited fields in one Existing batch still count as ONE Apply batch")
    func twoEditedFieldsCountAsOneBatch() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff, pulseDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])

        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "预打/生长次数")

        #expect(store.registryGrowthImportExistingFieldEdits["LNO12"]?.count == 2)
        #expect(store.registryGrowthImportApplyCount == 1)
    }

    @Test("F. 20 selected Ready batches + two edited Existing batches → Apply count 22")
    func readyPlusExistingApplyCount() {
        let store = LibraryFeatureStore()
        var items: [RegistryGrowthImportItem] = (1...20).map { index in
            RegistryGrowthImportItem(
                batchId: "LNO\(index)", sourceNotePaths: [], targetSheetHint: "LNO",
                action: .appendNewRow(targetSheet: "LNO"), columnValues: [:], provenance: [],
                blankColumns: [], expectedSampleKeys: ["LNO\(index)|o|STO|001"], warnings: [], blockingReasons: []
            )
        }
        items.append(existingItem(batchId: "LNO12X", differences: [dateDiff]))
        items.append(existingItem(batchId: "LNO13X", differences: [pulseDiff]))
        let plan = makePlan(items: items)
        store.registryGrowthImportPlan = plan
        store.registryGrowthImportSelectedReadyBatchIds = Set((1...20).map { "LNO\($0)" })
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12X", header: "日期")
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO13X", header: "预打/生长次数")

        #expect(store.registryGrowthImportApplyCount == 22)
    }

    @Test("If there are zero Ready selections but one Existing batch has edits, Apply count is 1")
    func onlyExistingEditsStillCounts() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")

        #expect(store.registryGrowthImportSelectedReadyBatchIds.isEmpty)
        #expect(store.registryGrowthImportApplyCount == 1)
    }

    // MARK: - G. Refresh clears stale pending Existing edits

    @Test("G. Closing the sheet clears pending Existing field edits")
    func closingSheetClearsPendingEdits() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")
        #expect(!store.registryGrowthImportExistingFieldEdits.isEmpty)

        store.closeRegistryGrowthImportSheet()

        #expect(store.registryGrowthImportExistingFieldEdits.isEmpty)
    }

    @Test("G2. Starting a preview rebuild clears pending Existing field edits from the previous plan")
    func rebuildingPreviewClearsPendingEdits() {
        let store = LibraryFeatureStore()
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        store.registryGrowthImportPlan = makePlan(items: [item])
        store.useObsidianValueForRegistryGrowthImportExistingField(batchId: "LNO12", header: "日期")
        #expect(!store.registryGrowthImportExistingFieldEdits.isEmpty)

        store.librarySettings.obsidianExperimentVaultPath = "/tmp/vault"
        store.resolveRegistrySourceURL = { URL(fileURLWithPath: "/tmp/registry.xlsx") }
        store.prepareRegistryGrowthImportPreview()

        #expect(store.registryGrowthImportExistingFieldEdits.isEmpty)
    }

    // MARK: - buildExistingFieldEdits: stale entries never reach the mutation service

    @Test("A stale pending edit whose header is no longer a planned difference is excluded from buildExistingFieldEdits")
    func staleEditExcludedFromBuild() {
        let item = existingItem(batchId: "LNO12", differences: [dateDiff])
        let plan = makePlan(items: [item])
        let pending: [String: [String: String]] = ["LNO12": ["日期": "2026.1.12", "不存在的列": "999"]]

        let edits = LibraryFeatureStore.buildExistingFieldEdits(plan: plan, pending: pending)

        #expect(edits.count == 1)
        #expect(edits.first?.columnHeader == "日期")
    }
}
