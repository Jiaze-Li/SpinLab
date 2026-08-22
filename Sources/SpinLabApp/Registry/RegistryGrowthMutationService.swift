import CoreXLSX
import Foundation

/// Executes a subset of a previously-built `RegistryGrowthImportPlan`
/// against the real Registry workbook. This is the only type in Phase 5A
/// allowed to write to the Registry — the planner never does (spec §1/§22).
///
/// Deliberately separate from `LibraryXLSXSyncService.syncEditedSample`
/// (spec §11): that method mutates an *existing* Sample's row under the
/// Phase 3A ownership guard; this service creates/fills *Batch growth*
/// rows, a different mutation semantic entirely. Both reuse the same
/// low-level OOXML primitives (`XLSXWorkbookKit`), never each other's
/// higher-level entry points.
struct RegistryGrowthMutationService {
    private let fileManager = FileManager.default
    /// Injectable so tests can supply an isolated rule source (bundled/temp
    /// Rules Book) instead of racing other tests through the mutable
    /// `SpinLabRuleProvider.shared` singleton — see
    /// docs/architecture/TESTING_STRATEGY.md "Rules Test Guidance".
    /// Production call sites use the default.
    private let ruleProvider: any SpinLabRuleProviding

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        self.ruleProvider = ruleProvider
    }

    func apply(plan: RegistryGrowthImportPlan, selectedBatchIds: [String], registryURL: URL) throws -> RegistryGrowthApplyResult {
        // TOCTOU guard (spec §3): the plan is a snapshot. If the workbook
        // changed since the plan was built — including a manual edit the
        // planner never saw — abort before touching anything.
        let currentFingerprint = try XLSXWorkbookKit.contentFingerprint(of: registryURL)
        guard currentFingerprint == plan.registryFingerprint else {
            throw RegistryGrowthMutationError.staleFingerprint(planFingerprint: plan.registryFingerprint, currentFingerprint: currentFingerprint)
        }

        var itemsByBatchId: [String: RegistryGrowthImportItem] = [:]
        for item in plan.items { itemsByBatchId[item.batchId] = item }

        var selectedItems: [RegistryGrowthImportItem] = []
        for batchId in selectedBatchIds {
            guard let item = itemsByBatchId[batchId] else {
                throw RegistryGrowthMutationError.itemNotFound(batchId: batchId)
            }
            guard item.isExecutable else {
                throw RegistryGrowthMutationError.itemNotExecutable(batchId: batchId, action: String(describing: item.action))
            }
            selectedItems.append(item)
        }
        guard !selectedItems.isEmpty else {
            return RegistryGrowthApplyResult(appliedBatchIds: [], backupPath: "")
        }

        // No sheet creation, ever (spec §15) — every selected item's target
        // sheet must already exist in the live workbook, re-checked here
        // independent of what the plan recorded.
        let liveSheetNames = try Self.sheetNames(of: registryURL)
        for item in selectedItems {
            guard let sheet = item.targetSheetHint, liveSheetNames.contains(sheet) else {
                throw RegistryGrowthMutationError.targetSheetMissing(sheetName: item.targetSheetHint ?? "?")
            }
        }

        let itemsBySheet = Dictionary(grouping: selectedItems, by: { $0.targetSheetHint! })

        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: registryURL)
        defer { try? fileManager.removeItem(at: workDir) }

        let workbook = try XLSXWorkbookKit.loadWorkbook(in: workDir)
        var touchedRefsBySheet: [String: Set<String>] = [:]
        var expectedValuesBySheet: [String: [String: String]] = [:]
        var beforeSnapshotBySheet: [String: [String: CellSnapshot]] = [:]
        var sheetPathByName: [String: String] = [:]

        for (sheetName, sheetItems) in itemsBySheet {
            let sheetPath = try XLSXWorkbookKit.worksheetPath(named: sheetName, workbook: workbook)
            sheetPathByName[sheetName] = sheetPath
            var doc = try XLSXWorkbookKit.loadXML(at: workDir.appending(path: sheetPath))

            beforeSnapshotBySheet[sheetName] = Self.snapshotSheet(doc)

            let headerMap = XLSXWorkbookKit.headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)
            var touchedRefs: Set<String> = []
            var expectedValues: [String: String] = [:]

            for item in sheetItems {
                switch item.action {
                case let .fillReservedRow(_, rowNumber):
                    try Self.fillReservedRow(
                        item: item, rowNumber: rowNumber, doc: &doc, headerMap: headerMap,
                        touchedRefs: &touchedRefs, expectedValues: &expectedValues
                    )
                case .appendNewRow:
                    try Self.appendRow(
                        item: item, doc: &doc, headerMap: headerMap,
                        touchedRefs: &touchedRefs, expectedValues: &expectedValues
                    )
                case .skipExisting, .blocked:
                    throw RegistryGrowthMutationError.itemNotExecutable(batchId: item.batchId, action: String(describing: item.action))
                }
            }

            touchedRefsBySheet[sheetName] = touchedRefs
            expectedValuesBySheet[sheetName] = expectedValues
            try XLSXWorkbookKit.saveXML(doc, to: workDir.appending(path: sheetPath))
        }

        try XLSXWorkbookKit.saveWorkbook(workbook, in: workDir)

        let backupURL = try XLSXWorkbookKit.commitTransaction(workDir: workDir, sourceURL: registryURL) { candidateURL in
            try Self.validateCandidate(
                candidateURL: candidateURL,
                expectedSheetNames: liveSheetNames,
                sheetPathByName: sheetPathByName,
                beforeSnapshotBySheet: beforeSnapshotBySheet,
                touchedRefsBySheet: touchedRefsBySheet,
                expectedValuesBySheet: expectedValuesBySheet
            )
            // Obsidian→Registry success invariant (spec): the candidate must
            // already be a valid input to Registry→Library — via the real
            // `LibraryRegistryParser`, never a duplicated parsing/comparison
            // implementation — before it is allowed to become the real
            // Registry. A candidate that fails this never gets to
            // `backup`/`replaceItemAt` below (see `commitTransaction`).
            let violations = try self.validateLibraryReadContract(xlsxURL: candidateURL, appliedItems: selectedItems)
            guard violations.isEmpty else {
                throw RegistryGrowthMutationError.candidateLibraryContractFailed(violations.joined(separator: " | "))
            }
        }

        try postApplyValidate(appliedItems: selectedItems, registryURL: registryURL, backupPath: backupURL.path)

        return RegistryGrowthApplyResult(appliedBatchIds: selectedItems.map(\.batchId), backupPath: backupURL.path)
    }

    // MARK: - Row mutation

    private static func fillReservedRow(
        item: RegistryGrowthImportItem,
        rowNumber: Int,
        doc: inout XMLDocument,
        headerMap: [String: String],
        touchedRefs: inout Set<String>,
        expectedValues: inout [String: String]
    ) throws {
        guard let batchIdHeader = RegistryGrowthFieldMapping.header(for: .batchId, availableHeaders: Set(headerMap.keys)),
              let idColumn = headerMap[batchIdHeader] else {
            throw RegistryGrowthMutationError.rowValidationFailed(batchId: item.batchId, reason: "编号 column not found on target sheet.")
        }
        // Verify identity before writing anything — never rewrite/guess a
        // mismatched id (spec §14: "编号本身不需要重写，除非验证一致").
        let rowElements = XLSXWorkbookKit.dataRows(in: doc).filter { XLSXWorkbookKit.rowNumber(of: $0) == rowNumber }
        guard let rowElement = rowElements.first else {
            throw RegistryGrowthMutationError.rowValidationFailed(batchId: item.batchId, reason: "Reserved row \(rowNumber) not found at apply time.")
        }
        let existingId = XLSXWorkbookKit.rowValueMap(row: rowElement, headerMap: [batchIdHeader: idColumn], sharedStrings: [])[batchIdHeader]
        guard existingId?.trimmingCharacters(in: .whitespacesAndNewlines) == item.batchId else {
            throw RegistryGrowthMutationError.rowValidationFailed(batchId: item.batchId, reason: "Reserved row \(rowNumber)'s 编号 no longer matches the planned batch id.")
        }

        for (header, value) in item.columnValues where header != batchIdHeader {
            guard let column = headerMap[header] else { continue }
            XLSXWorkbookKit.setCellValue(doc: &doc, row: rowNumber, column: column, value: value)
            let ref = "\(column)\(rowNumber)"
            touchedRefs.insert(ref)
            expectedValues[ref] = value
        }
    }

    private static func appendRow(
        item: RegistryGrowthImportItem,
        doc: inout XMLDocument,
        headerMap: [String: String],
        touchedRefs: inout Set<String>,
        expectedValues: inout [String: String]
    ) throws {
        let existingRows = XLSXWorkbookKit.dataRows(in: doc)
        guard let batchIdHeader = RegistryGrowthFieldMapping.header(for: .batchId, availableHeaders: Set(headerMap.keys)),
              let idColumn = headerMap[batchIdHeader] else {
            throw RegistryGrowthMutationError.rowValidationFailed(batchId: item.batchId, reason: "编号 column not found on target sheet.")
        }

        // Nearest existing *normal* data row (id present, and at least one
        // other mapped growth column non-empty) becomes the style template.
        // Never the row's actual values — only its per-cell/per-row style
        // structure is copied (spec §13).
        let candidateFields = RegistryGrowthFieldMapping.Field.allCases.filter { $0 != .batchId }
        let candidateColumns = candidateFields.compactMap { field -> String? in
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: Set(headerMap.keys)) else { return nil }
            return headerMap[header]
        }
        let candidateColumnHeaderMap = Dictionary(uniqueKeysWithValues: candidateColumns.map { ($0, $0) })
        let templateRow = existingRows
            .filter { row in
                let idValue = XLSXWorkbookKit.rowValueMap(row: row, headerMap: [batchIdHeader: idColumn], sharedStrings: [])[batchIdHeader]
                guard XLSXWorkbookKit.nonEmpty(idValue) != nil else { return false }
                let values = XLSXWorkbookKit.rowValueMap(row: row, headerMap: candidateColumnHeaderMap, sharedStrings: [])
                return candidateColumns.contains { column in XLSXWorkbookKit.nonEmpty(values[column]) != nil }
            }
            .max { (a, b) in (XLSXWorkbookKit.rowNumber(of: a) ?? 0) < (XLSXWorkbookKit.rowNumber(of: b) ?? 0) }

        let maxRow = existingRows.compactMap { XLSXWorkbookKit.rowNumber(of: $0) }.max() ?? 1
        let nextRow = maxRow + 1

        if let templateRow {
            XLSXWorkbookKit.setRowStyle(doc: &doc, row: nextRow, style: XLSXWorkbookKit.rowStyleAttribute(row: templateRow))
            let templateColumns = (templateRow.children ?? []).compactMap { child -> String? in
                guard let el = child as? XMLElement, el.name == "c", let ref = el.attribute(forName: "r")?.stringValue else { return nil }
                return XLSXWorkbookKit.columnPart(of: ref)
            }
            for column in templateColumns {
                let style = XLSXWorkbookKit.cellStyleAttribute(row: templateRow, column: column)
                XLSXWorkbookKit.setCellStyle(doc: &doc, row: nextRow, column: column, style: style)
            }
        }

        for (header, value) in item.columnValues {
            guard let column = headerMap[header] else { continue }
            XLSXWorkbookKit.setCellValue(doc: &doc, row: nextRow, column: column, value: value)
            let ref = "\(column)\(nextRow)"
            touchedRefs.insert(ref)
            expectedValues[ref] = value
        }
    }

    // MARK: - Candidate validation (spec §17)

    struct CellSnapshot: Equatable {
        var value: String?
        var style: String?
    }

    private static func snapshotSheet(_ doc: XMLDocument) -> [String: CellSnapshot] {
        var snapshot: [String: CellSnapshot] = [:]
        let allRows = (try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']"))?.compactMap { $0 as? XMLElement } ?? []
        for row in allRows {
            for case let cell as XMLElement in (row.children ?? []) where cell.name == "c" {
                guard let ref = cell.attribute(forName: "r")?.stringValue else { continue }
                // Note: no sharedStrings available for a standalone worksheet
                // doc snapshot; inlineStr/numeric cells still compare fine,
                // and every write in this file always produces inlineStr —
                // a pre-existing shared-string cell that is *not* touched
                // is compared by its raw shared-string index, which is
                // stable across the untouched candidate too.
                let value = XLSXWorkbookKit.readCellValue(cell: cell, sharedStrings: [])
                    ?? (try? cell.nodes(forXPath: "./*[local-name()='v']").first as? XMLElement)?.stringValue
                let style = cell.attribute(forName: "s")?.stringValue
                snapshot[ref] = CellSnapshot(value: value, style: style)
            }
        }
        return snapshot
    }

    private static func validateCandidate(
        candidateURL: URL,
        expectedSheetNames: [String],
        sheetPathByName: [String: String],
        beforeSnapshotBySheet: [String: [String: CellSnapshot]],
        touchedRefsBySheet: [String: Set<String>],
        expectedValuesBySheet: [String: [String: String]]
    ) throws {
        // 1. Archive/workbook must reparse cleanly.
        guard let file = XLSXFile(filepath: candidateURL.path) else {
            throw RegistryGrowthMutationError.candidateValidationFailed("Candidate is not a valid zip/xlsx archive.")
        }
        guard let workbook = try? file.parseWorkbooks().first else {
            throw RegistryGrowthMutationError.candidateValidationFailed("CoreXLSX could not reparse the candidate workbook.")
        }

        // 2. Sheet list/order unchanged, no unexpected new sheet.
        let candidateWorkDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: candidateURL)
        defer { try? FileManager.default.removeItem(at: candidateWorkDir) }
        let candidateContext = try XLSXWorkbookKit.loadWorkbook(in: candidateWorkDir)
        let candidateSheetNames = try XLSXWorkbookKit.sheetNames(workbook: candidateContext)
        guard candidateSheetNames == expectedSheetNames else {
            throw RegistryGrowthMutationError.unexpectedSheetChange("Sheet list/order changed: expected \(expectedSheetNames), got \(candidateSheetNames).")
        }

        // 3. Per-sheet: expected planned cells equal expected values; every
        //    other cell (value + style) equal to the pre-mutation snapshot.
        for (sheetName, sheetPath) in sheetPathByName {
            let doc = try XLSXWorkbookKit.loadXML(at: candidateWorkDir.appending(path: sheetPath))
            let afterSnapshot = snapshotSheet(doc)
            let before = beforeSnapshotBySheet[sheetName] ?? [:]
            let touched = touchedRefsBySheet[sheetName] ?? []
            let expected = expectedValuesBySheet[sheetName] ?? [:]

            for (ref, expectedValue) in expected {
                guard afterSnapshot[ref]?.value == expectedValue else {
                    throw RegistryGrowthMutationError.candidateValidationFailed("Cell \(ref) on sheet \(sheetName) does not equal the planned value.")
                }
            }

            for (ref, beforeCell) in before where !touched.contains(ref) {
                guard afterSnapshot[ref] == beforeCell else {
                    throw RegistryGrowthMutationError.unexpectedSheetChange("Unrelated cell \(ref) on sheet \(sheetName) changed value or style unexpectedly.")
                }
            }
        }
        _ = workbook
    }

    // MARK: - Library read-contract validation (shared pre-replace/post-replace)

    /// The Obsidian→Registry success invariant: the committed Registry must
    /// be a valid input to the existing Registry→Library parser
    /// (`LibraryRegistryParser` — never a second/duplicated parsing
    /// implementation) and must produce, for every applied item, exactly the
    /// expected Batch/Sample identity:
    ///   - the Batch is readable at all (a Batch can parse even when its
    ///     substrate fails to produce a Sample, so Batch presence alone is
    ///     not sufficient evidence — Phase 5A review blocker #3),
    ///   - the Batch landed on its expected target sheet, where the item has
    ///     one, and
    ///   - the Batch's parsed Sample keys are exactly (set equality, order
    ///     irrelevant) `item.expectedSampleKeys` — neither missing a key nor
    ///     carrying an extra one for the same batch.
    /// Called identically on the *candidate* file before the atomic replace
    /// and on the real Registry after it (`postApplyValidate` below) — one
    /// implementation, two call sites, per the invariant's own wording.
    private func validateLibraryReadContract(xlsxURL: URL, appliedItems: [RegistryGrowthImportItem]) throws -> [String] {
        let settings = LibrarySettings(
            rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil,
            registrySourcePath: xlsxURL.path, backupPath: nil, backupLastSyncedAt: nil,
            allowedBatchPrefixes: [], lastRefreshAt: nil
        )
        let parsed = try LibraryRegistryParser(ruleProvider: ruleProvider).parse(xlsxURL: xlsxURL, settings: settings)
        let batchesById = Dictionary(uniqueKeysWithValues: parsed.index.batches.map { ($0.id, $0) })
        let samplesByKey = Dictionary(uniqueKeysWithValues: parsed.index.samples.map { ($0.id, $0) })

        var messages: [String] = []
        for item in appliedItems {
            guard let batch = batchesById[item.batchId] else {
                messages.append("Batch \(item.batchId) not readable by Registry → Library parser.")
                continue
            }

            if let targetSheet = item.targetSheetHint, batch.sheetName != targetSheet {
                messages.append("Batch \(item.batchId) parsed onto sheet \"\(batch.sheetName)\", expected target sheet \"\(targetSheet)\".")
            }

            let actualKeys = Set(batch.sampleKeys)
            let expectedKeys = Set(item.expectedSampleKeys)
            if actualKeys != expectedKeys {
                var detail: [String] = []
                let missing = expectedKeys.subtracting(actualKeys).sorted()
                let unexpected = actualKeys.subtracting(expectedKeys).sorted()
                if !missing.isEmpty { detail.append("missing \(missing.joined(separator: ", "))") }
                if !unexpected.isEmpty { detail.append("unexpected \(unexpected.joined(separator: ", "))") }
                messages.append("Batch \(item.batchId) Sample key set does not exactly match expected (\(detail.joined(separator: "; "))).")
            }

            // Registry metadata round-trip: every header this item wrote must
            // read back identically through `LibraryBatch.metadata` — the
            // same row-level dict `LibraryRegistryParser.parse` builds via
            // `XLSXSheetValueReader.rowMetadata`, which projects *every*
            // non-empty header/value cell on the row (no header is excluded
            // from this projection by parser contract), so every key in
            // `item.columnValues` is expected to be present and equal.
            for (header, expectedValue) in item.columnValues {
                guard batch.metadata[header] == expectedValue else {
                    let actual = batch.metadata[header].map { "\"\($0)\"" } ?? "missing"
                    messages.append("Batch \(item.batchId) metadata[\"\(header)\"] = \(actual), expected \"\(expectedValue)\".")
                    continue
                }
            }

            // Sample metadata round-trip: `LibrarySample.metadata` is the
            // same row-level dict projected per-Sample rather than
            // per-Batch (see `LibraryRegistryParser.parse`), so it must carry
            // this item's written values too, for every canonical Sample the
            // item is expected to have produced (already confirmed present
            // above by the Sample-key-set check).
            for sampleKey in item.expectedSampleKeys {
                guard let sample = samplesByKey[sampleKey] else { continue }
                for (header, expectedValue) in item.columnValues {
                    guard sample.metadata[header] == expectedValue else {
                        let actual = sample.metadata[header].map { "\"\($0)\"" } ?? "missing"
                        messages.append("Sample \(sampleKey) metadata[\"\(header)\"] = \(actual), expected \"\(expectedValue)\".")
                        continue
                    }
                }
            }
        }
        return messages
    }

    // MARK: - Post-replace validation (spec §18)

    /// Re-runs `validateLibraryReadContract` against the real, now-replaced
    /// Registry file — the candidate already passed the identical check
    /// before replace (see `apply` above), but the real file is re-verified
    /// independently rather than assumed identical to the candidate.
    private func postApplyValidate(appliedItems: [RegistryGrowthImportItem], registryURL: URL, backupPath: String) throws {
        do {
            let violations = try validateLibraryReadContract(xlsxURL: registryURL, appliedItems: appliedItems)
            guard violations.isEmpty else {
                throw RegistryGrowthMutationError.postApplyValidationFailed(violations.joined(separator: " | "), backupPath: backupPath)
            }
        } catch let error as RegistryGrowthMutationError {
            throw error
        } catch {
            throw RegistryGrowthMutationError.postApplyValidationFailed(String(describing: error), backupPath: backupPath)
        }
    }

    private static func sheetNames(of url: URL) throws -> [String] {
        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let workbook = try XLSXWorkbookKit.loadWorkbook(in: workDir)
        return try XLSXWorkbookKit.sheetNames(workbook: workbook)
    }
}
