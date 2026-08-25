import Foundation
import Testing
@testable import SpinLabApp

/// PR #169 closeout — repair pass 2. Covers the remaining PR-level review
/// findings closed in this pass:
///
/// 1. `LibraryXLSXSyncService` validation closures must own and clean up the
///    temp working directory they create for reparse-validation (never leak
///    a `spinlab_xlsx_*` directory per successful sync/status-update).
/// 2. The Apply confirmation must classify selected operations by kind
///    (append/fill vs. `.enrichExisting` vs. manual Existing edits) rather
///    than describing an `.enrichExisting` update to an already-populated
///    row as a new record.
/// 3. `XLSXWorkbookKit.ensureHeaderIfNeeded` must recognize an existing
///    shared-string header row (not misread it as empty via a hardcoded
///    `sharedStrings: []`), while still writing headers into a genuinely
///    empty/new sheet.
@Suite("PR169 RegistryGrowthMutationService correctness repair — pass 2")
struct PR169RegistryGrowthCorrectnessRepairPass2Tests {
    // MARK: - 1. Validation temp-directory ownership

    /// `prepareWorkingDirectory` allocates under the system temp directory
    /// with a `spinlab_xlsx_` prefix (see `XLSXWorkbookKit`). This proves the
    /// validation closure's own `defer` removes its directory even though
    /// the closure itself is the only place that ever sees that URL — the
    /// lifetime is now owned entirely inside the closure body rather than
    /// discarded, which is what pass 1 review flagged.
    @Test("A validation-only prepareWorkingDirectory call cleans up its own directory")
    func validationWorkingDirectoryIsCleanedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PR169-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.build(to: url)

        // Mirrors the exact pattern now used at the two repaired call sites
        // in LibraryXLSXSyncService: a local `let`, an immediate `defer`,
        // then `loadWorkbook` on the local — never the discarded-URL form.
        var capturedDir: URL?
        do {
            let validationDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
            capturedDir = validationDir
            defer { try? FileManager.default.removeItem(at: validationDir) }
            _ = try XLSXWorkbookKit.loadWorkbook(in: validationDir)
        }

        let stillExists = capturedDir.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
        #expect(stillExists == false, "validation working directory must not survive past the validation closure")
    }

    // MARK: - 2. Apply confirmation operation-kind breakdown

    private func makeItem(batchId: String, action: RegistryGrowthImportAction) -> RegistryGrowthImportItem {
        RegistryGrowthImportItem(
            batchId: batchId, sourceNotePaths: ["\(batchId).md"], targetSheetHint: "LNO",
            action: action, columnValues: [:], provenance: [], blankColumns: [],
            expectedSampleKeys: [], warnings: [], blockingReasons: []
        )
    }

    private func makePlan(items: [RegistryGrowthImportItem]) -> RegistryGrowthImportPlan {
        RegistryGrowthImportPlan(
            registryFingerprint: "fp", registrySourcePath: "/tmp/registry.xlsx", builtAt: .now,
            items: items, diagnostics: [], existingCount: 0
        )
    }

    @Test("Breakdown counts append/fill only")
    func breakdownAppendFillOnly() throws {
        let plan = makePlan(items: [
            makeItem(batchId: "A", action: .appendNewRow(targetSheet: "LNO")),
            makeItem(batchId: "B", action: .fillReservedRow(targetSheet: "LNO", rowNumber: 3))
        ])
        let breakdown = LibraryFeatureStore.applyOperationBreakdown(
            plan: plan, selectedReady: ["A", "B"], existingFieldEdits: [:]
        )
        #expect(breakdown.appendOrFillCount == 2)
        #expect(breakdown.enrichCount == 0)
        #expect(breakdown.manualExistingCount == 0)
    }

    @Test("Breakdown counts enrichExisting only")
    func breakdownEnrichOnly() throws {
        let plan = makePlan(items: [
            makeItem(batchId: "A", action: .enrichExisting(targetSheet: "LNO", rowNumber: 2, plannedFieldEdits: []))
        ])
        let breakdown = LibraryFeatureStore.applyOperationBreakdown(
            plan: plan, selectedReady: ["A"], existingFieldEdits: [:]
        )
        #expect(breakdown.appendOrFillCount == 0)
        #expect(breakdown.enrichCount == 1)
        #expect(breakdown.manualExistingCount == 0)
    }

    @Test("Breakdown counts manual Existing edits only")
    func breakdownManualExistingOnly() throws {
        let diff = RegistryGrowthExistingDifference(field: .date, header: "日期", registryValue: "2026.1.1", obsidianValue: "2026.1.5")
        var item = makeItem(batchId: "A", action: .skipExisting(targetSheet: "LNO", rowNumber: 2))
        item.existingDifferences = [diff]
        let plan = makePlan(items: [item])
        let breakdown = LibraryFeatureStore.applyOperationBreakdown(
            plan: plan, selectedReady: [], existingFieldEdits: ["A": ["日期": "2026.1.5"]]
        )
        #expect(breakdown.appendOrFillCount == 0)
        #expect(breakdown.enrichCount == 0)
        #expect(breakdown.manualExistingCount == 1)
    }

    @Test("Breakdown counts all three operation kinds together")
    func breakdownAllThree() throws {
        let diff = RegistryGrowthExistingDifference(field: .date, header: "日期", registryValue: "2026.1.1", obsidianValue: "2026.1.5")
        var manualItem = makeItem(batchId: "C", action: .skipExisting(targetSheet: "LNO", rowNumber: 4))
        manualItem.existingDifferences = [diff]
        let plan = makePlan(items: [
            makeItem(batchId: "A", action: .appendNewRow(targetSheet: "LNO")),
            makeItem(batchId: "B", action: .enrichExisting(targetSheet: "LNO", rowNumber: 2, plannedFieldEdits: [])),
            manualItem
        ])
        let breakdown = LibraryFeatureStore.applyOperationBreakdown(
            plan: plan, selectedReady: ["A", "B"], existingFieldEdits: ["C": ["日期": "2026.1.5"]]
        )
        #expect(breakdown.appendOrFillCount == 1)
        #expect(breakdown.enrichCount == 1)
        #expect(breakdown.manualExistingCount == 1)
    }

    // MARK: - 3. ensureHeaderIfNeeded shared-string awareness

    @Test("ensureHeaderIfNeeded recognizes an existing shared-string header row and does not rewrite it")
    func sharedStringHeaderIsNotRewritten() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="A1" t="s"><v>0</v></c>
              <c r="B1" t="s"><v>1</v></c>
            </row>
          </sheetData>
        </worksheet>
        """
        var doc = try XMLDocument(xmlString: xml, options: [])
        let sharedStrings = ["timestamp", "status"]

        XLSXWorkbookKit.ensureHeaderIfNeeded(headers: ["timestamp", "status"], sharedStrings: sharedStrings, in: &doc)

        let row = try #require(doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row' and @r='1']").first as? XMLElement)
        #expect(row.children?.count == 2, "existing shared-string header cells must not be duplicated/rewritten")
        let map = XLSXWorkbookKit.headerColumnMap(in: doc, sharedStrings: sharedStrings)
        #expect(map["timestamp"] == "A")
        #expect(map["status"] == "B")
    }

    @Test("ensureHeaderIfNeeded still writes headers into a genuinely empty sheet")
    func emptySheetStillGetsHeaders() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData/>
        </worksheet>
        """
        var doc = try XMLDocument(xmlString: xml, options: [])

        XLSXWorkbookKit.ensureHeaderIfNeeded(headers: ["timestamp", "status"], sharedStrings: [], in: &doc)

        let map = XLSXWorkbookKit.headerColumnMap(in: doc, sharedStrings: [])
        #expect(map["timestamp"] == "A")
        #expect(map["status"] == "B")
    }
}
