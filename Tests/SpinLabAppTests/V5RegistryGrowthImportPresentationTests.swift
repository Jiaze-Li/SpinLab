import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5B: `RegistryGrowthImportPresentation` coverage — pure enum → UI
/// projection only. Never exercises the planner/mutation pipeline; every
/// item here is a hand-built literal so these tests stay fast and immune to
/// Rules/Registry fixture drift.
@Suite("V5.4.6 RegistryGrowthImportPresentation")
struct V5RegistryGrowthImportPresentationTests {
    private func item(batchId: String = "LNO14", action: RegistryGrowthImportAction, columnValues: [String: String] = [:], blockingReasons: [RegistryGrowthBlockingReason] = []) -> RegistryGrowthImportItem {
        RegistryGrowthImportItem(
            batchId: batchId,
            sourceNotePaths: ["\(batchId).md"],
            targetSheetHint: "LNO",
            action: action,
            columnValues: columnValues,
            provenance: [],
            blankColumns: [],
            expectedSampleKeys: [],
            warnings: [],
            blockingReasons: blockingReasons
        )
    }

    // MARK: - 1/2/3/4. Filter mapping

    @Test("1. appendNewRow → Ready")
    func appendMapsToReady() {
        #expect(RegistryGrowthImportPresentation.filter(for: item(action: .appendNewRow(targetSheet: "LNO"))) == .ready)
    }

    @Test("2. fillReservedRow → Ready")
    func fillReservedMapsToReady() {
        #expect(RegistryGrowthImportPresentation.filter(for: item(action: .fillReservedRow(targetSheet: "LNO", rowNumber: 5))) == .ready)
    }

    @Test("3. skipExisting → Existing")
    func skipExistingMapsToExisting() {
        #expect(RegistryGrowthImportPresentation.filter(for: item(action: .skipExisting(targetSheet: "LNO", rowNumber: 5))) == .existing)
    }

    @Test("4. blocked → Blocked")
    func blockedMapsToBlocked() {
        #expect(RegistryGrowthImportPresentation.filter(for: item(action: .blocked(reasons: [.missingDate]))) == .blocked)
    }

    // MARK: - 14. UI presentation never changes the Planner action

    @Test("14. Presentation projections never mutate or reinterpret the underlying action")
    func presentationDoesNotChangeAction() {
        let original = item(action: .appendNewRow(targetSheet: "LNO"))
        _ = RegistryGrowthImportPresentation.filter(for: original)
        _ = RegistryGrowthImportPresentation.actionTitle(for: original)
        _ = RegistryGrowthImportPresentation.summarySubtitle(for: original)
        #expect(original.action == .appendNewRow(targetSheet: "LNO"))
    }

    // MARK: - 15. Blocking reason formatter covers every enum case

    @Test("15a. missingBatchId formats to non-empty text")
    func missingBatchIdText() {
        #expect(!RegistryGrowthImportPresentation.blockingReasonText(.missingBatchId).isEmpty)
    }

    @Test("15b. missingDate formats to non-empty text")
    func missingDateText() {
        #expect(!RegistryGrowthImportPresentation.blockingReasonText(.missingDate).isEmpty)
    }

    @Test("15c. missingMaterialEvidence formats to non-empty text")
    func missingMaterialText() {
        #expect(!RegistryGrowthImportPresentation.blockingReasonText(.missingMaterialEvidence).isEmpty)
    }

    @Test("15d. missingSubstrateEvidence formats to non-empty text")
    func missingSubstrateText() {
        #expect(!RegistryGrowthImportPresentation.blockingReasonText(.missingSubstrateEvidence).isEmpty)
    }

    @Test("15e. unresolvedSubstrateIdentity includes the raw hint when present")
    func unresolvedSubstrateText() {
        let withHint = RegistryGrowthImportPresentation.blockingReasonText(.unresolvedSubstrateIdentity(rawHint: "FooBar"))
        #expect(withHint.contains("FooBar"))
        let withoutHint = RegistryGrowthImportPresentation.blockingReasonText(.unresolvedSubstrateIdentity(rawHint: nil))
        #expect(!withoutHint.isEmpty)
    }

    @Test("15f. unroutableMaterialOrPrefix includes the raw hint when present")
    func unroutableText() {
        let withHint = RegistryGrowthImportPresentation.blockingReasonText(.unroutableMaterialOrPrefix(rawHint: "XYZ"))
        #expect(withHint.contains("XYZ"))
    }

    @Test("15g. targetSheetNotFound includes the sheet name")
    func targetSheetNotFoundText() {
        #expect(RegistryGrowthImportPresentation.blockingReasonText(.targetSheetNotFound(sheetName: "LSMO")).contains("LSMO"))
    }

    @Test("15h. duplicateRegistryRow includes sheet and row numbers")
    func duplicateRowText() {
        let text = RegistryGrowthImportPresentation.blockingReasonText(.duplicateRegistryRow(sheet: "LNO", rowNumbers: [3, 7]))
        #expect(text.contains("LNO"))
        #expect(text.contains("3"))
        #expect(text.contains("7"))
    }

    @Test("15i. obsidianInternalConflict includes the field name")
    func obsidianInternalConflictText() {
        #expect(RegistryGrowthImportPresentation.blockingReasonText(.obsidianInternalConflict(field: "growthDate")).contains("growthDate"))
    }

    @Test("15j. obsidianDateConflict formats to non-empty text")
    func obsidianDateConflictText() {
        #expect(!RegistryGrowthImportPresentation.blockingReasonText(.obsidianDateConflict).isEmpty)
    }

    @Test("15k. libraryObsidianConflictOnExistingBatch includes the field name")
    func libraryObsidianConflictText() {
        #expect(RegistryGrowthImportPresentation.blockingReasonText(.libraryObsidianConflictOnExistingBatch(field: "substrate")).contains("substrate"))
    }

    @Test("15l. other passes the message through")
    func otherReasonText() {
        #expect(RegistryGrowthImportPresentation.blockingReasonText(.other("custom reason")) == "custom reason")
    }

    // MARK: - summarySubtitle only surfaces already-resolved columnValues

    @Test("summarySubtitle only reflects already-resolved columnValues, never re-derives them")
    func summarySubtitleReflectsColumnValues() {
        let sample = item(action: .appendNewRow(targetSheet: "LNO"), columnValues: [
            "日期": "2026.8.3", "substrate": "STO(001)", "生长温度": "650"
        ])
        let subtitle = RegistryGrowthImportPresentation.summarySubtitle(for: sample)
        #expect(subtitle.contains("2026.8.3"))
        #expect(subtitle.contains("STO(001)"))
        #expect(subtitle.contains("650"))
    }

    // MARK: - Phase 5B polish: action badges

    @Test("actionBadgeTitle: appendNewRow → NEW, fillReservedRow → FILL, skipExisting → EXISTING, blocked → BLOCKED")
    func actionBadgeTitles() {
        #expect(RegistryGrowthImportPresentation.actionBadgeTitle(for: item(action: .appendNewRow(targetSheet: "LNO"))) == "NEW")
        #expect(RegistryGrowthImportPresentation.actionBadgeTitle(for: item(action: .fillReservedRow(targetSheet: "LNO", rowNumber: 5))) == "FILL")
        #expect(RegistryGrowthImportPresentation.actionBadgeTitle(for: item(action: .skipExisting(targetSheet: "LNO", rowNumber: 5))) == "EXISTING")
        #expect(RegistryGrowthImportPresentation.actionBadgeTitle(for: item(action: .blocked(reasons: [.missingDate]))) == "BLOCKED")
    }

    // MARK: - Phase 5B polish: compact summary lines

    @Test("compactPrimaryLine surfaces substrate and date only")
    func compactPrimaryLineFields() {
        let sample = item(action: .appendNewRow(targetSheet: "LNO"), columnValues: [
            "日期": "2026.8.3", "substrate": "STO(001)", "生长温度": "650"
        ])
        let line = RegistryGrowthImportPresentation.compactPrimaryLine(for: sample)
        #expect(line.contains("STO(001)"))
        #expect(line.contains("2026.8.3"))
        #expect(!line.contains("650"))
    }

    @Test("compactSecondaryLine surfaces growth temperature, oxygen pressure, and energy only")
    func compactSecondaryLineFields() {
        let sample = item(action: .appendNewRow(targetSheet: "LNO"), columnValues: [
            "substrate": "STO(001)", "生长温度": "650", "氧压": "200mT", "能量": "80mJ"
        ])
        let line = RegistryGrowthImportPresentation.compactSecondaryLine(for: sample)
        #expect(line.contains("650"))
        #expect(line.contains("200mT"))
        #expect(line.contains("80mJ"))
        #expect(!line.contains("STO(001)"))
    }

    // MARK: - Phase 5B polish: ordered Registry Preview rows

    @Test("orderedRegistryPreviewRows follows the confirmed field mapping order, not alphabetical")
    func orderedRegistryPreviewRowsFollowsFieldOrder() {
        let sample = item(action: .appendNewRow(targetSheet: "LNO"), columnValues: [
            "氧压": "200mT", "编号": "LNO14", "日期": "2026.8.3", "substrate": "STO(001)"
        ])
        let rows = RegistryGrowthImportPresentation.orderedRegistryPreviewRows(for: sample)
        let headers = rows.map(\.header)
        #expect(headers == ["编号", "日期", "substrate", "氧压"])
    }

    @Test("orderedRegistryPreviewRows appends unmapped columns after the mapped ones, alphabetically, without dropping them")
    func orderedRegistryPreviewRowsAppendsUnmappedColumns() {
        let sample = item(action: .appendNewRow(targetSheet: "LNO"), columnValues: [
            "日期": "2026.8.3", "自定义列": "value"
        ])
        let rows = RegistryGrowthImportPresentation.orderedRegistryPreviewRows(for: sample)
        #expect(rows.map(\.header) == ["日期", "自定义列"])
        #expect(rows.count == sample.columnValues.count)
    }
}
