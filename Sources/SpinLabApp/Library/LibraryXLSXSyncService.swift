import Foundation

final class LibraryXLSXSyncService {
    enum SyncError: LocalizedError {
        case missingFile(path: String)
        case unzipFailed(String)
        case zipFailed(String)
        case invalidWorkbook(String)
        case missingSampleLocation(sampleId: String)
        case registryFieldsRejected(sampleId: String, keys: [String])
        case transactionFailed(String)

        var errorDescription: String? {
            switch self {
            case let .missingFile(path):
                return "Registry source file does not exist: \(path)"
            case let .unzipFailed(message):
                return "Registry sync failed: unzip failed (\(message))"
            case let .zipFailed(message):
                return "Registry sync failed: zip failed (\(message))"
            case let .invalidWorkbook(message):
                return "Registry sync failed: \(message)"
            case let .missingSampleLocation(sampleId):
                return "Sample \(sampleId) has no source sheet/row mapping."
            case let .registryFieldsRejected(sampleId, keys):
                return "Refused to write field(s) \(keys.joined(separator: ", ")) for sample \(sampleId): not confirmed Sample-owned (Batch-owned or unclassified), and the shared Batch row must not be mutated from a Sample edit."
            case let .transactionFailed(message):
                return "Registry sync failed: \(message)"
            }
        }
    }

    struct MetadataWrite {
        var key: String
        var oldValue: String?
        var newValue: String?
    }

    struct NumericLogWrite {
        var key: String
        var oldValue: String?
        var newValue: String?
    }

    private let fileManager = FileManager.default
    private let fieldOwnership: LibraryFieldOwnershipRuleBook

    init(fieldOwnership: LibraryFieldOwnershipRuleBook = .shared) {
        self.fieldOwnership = fieldOwnership
    }

    private static let metadataSheet = "__metadata_sync_log"
    private static let numericSheet = "__numeric_tags_log"

    private let metadataHeaders = [
        "timestamp", "sample_id", "batch_id", "sheet_name", "row_number",
        "column_name", "old_value", "new_value", "write_result", "error_message"
    ]

    private let numericHeaders = [
        "timestamp", "sample_id", "batch_id", "sheet_name", "row_number",
        "tag_key", "old_value", "new_value", "status", "status_changed_at", "status_changed_by"
    ]

    func syncEditedSample(
        oldSample: LibrarySample,
        updatedSample: LibrarySample,
        registrySourceURL: URL,
        metadataWrites: [MetadataWrite],
        numericWrites: [NumericLogWrite]
    ) throws -> LibraryRegistrySourceSyncResult {
        guard fileManager.fileExists(atPath: registrySourceURL.path) else {
            throw SyncError.missingFile(path: registrySourceURL.path)
        }
        guard let sampleSheet = updatedSample.sourceSheetName,
              let sampleRow = updatedSample.sourceRowNumber else {
            throw SyncError.missingSampleLocation(sampleId: updatedSample.id)
        }

        // Last-line-of-defense ownership check, before any workbook I/O.
        // Two independent sources must both clear the gate — neither one
        // alone is trustworthy:
        //   1. `metadataWrites` — the literal keys about to be written to
        //      the shared row. A caller could construct this list directly
        //      (bypassing LibrarySampleEditService.apply entirely), so it
        //      must be checked on its own regardless of what the sample
        //      diff says.
        //   2. oldSample/updatedSample.metadata diff — catches a caller
        //      that under-declares `metadataWrites` relative to what
        //      actually changed on the sample.
        // Checking only one of the two leaves a bypass: write-list-only
        // checking misses a real diff with an empty/wrong write list;
        // diff-only checking misses a forged write list paired with
        // oldSample == updatedSample (empty diff). Fail-closed: only a
        // confirmed Sample-owned field may pass; Batch-owned AND Unknown
        // are both rejected — an unclassified Registry column is never
        // silently written into the shared Batch row. See
        // docs/library-architecture-audit.md §13.6/F1.
        let changedMetadataKeys = Set(oldSample.metadata.keys).union(updatedSample.metadata.keys)
            .filter { oldSample.metadata[$0] != updatedSample.metadata[$0] }
        let rejectedFromWrites = fieldOwnership.nonSampleOwnedKeys(among: metadataWrites.map(\.key))
        let rejectedFromDiff = fieldOwnership.nonSampleOwnedKeys(among: changedMetadataKeys)
        let rejectedKeys = Set(rejectedFromWrites).union(rejectedFromDiff).sorted()
        guard rejectedKeys.isEmpty else {
            throw SyncError.registryFieldsRejected(sampleId: updatedSample.id, keys: rejectedKeys)
        }

        if metadataWrites.isEmpty, numericWrites.isEmpty {
            return LibraryRegistrySourceSyncResult(
                metadataWrittenCount: 0,
                metadataFailedCount: 0,
                manualLoggedCount: 0,
                metadataLogSheetName: Self.metadataSheet,
                manualLogSheetName: Self.numericSheet
            )
        }

        let workDir = try wrap { try XLSXWorkbookKit.prepareWorkingDirectory(for: registrySourceURL) }
        defer { try? fileManager.removeItem(at: workDir) }

        var workbook = try wrap { try XLSXWorkbookKit.loadWorkbook(in: workDir) }
        let timestamp = ISO8601DateFormatter().string(from: .now)

        let metadataPath = try wrap { try XLSXWorkbookKit.ensureSheet(named: Self.metadataSheet, in: &workbook, under: workDir) }
        let numericPath = try wrap { try XLSXWorkbookKit.ensureSheet(named: Self.numericSheet, in: &workbook, under: workDir) }
        let samplePath = try wrap { try XLSXWorkbookKit.worksheetPath(named: sampleSheet, workbook: workbook) }

        var metadataDoc = try wrap { try XLSXWorkbookKit.loadXML(at: workDir.appending(path: metadataPath)) }
        var numericDoc = try wrap { try XLSXWorkbookKit.loadXML(at: workDir.appending(path: numericPath)) }
        var sampleDoc = try wrap { try XLSXWorkbookKit.loadXML(at: workDir.appending(path: samplePath)) }

        XLSXWorkbookKit.ensureHeaderIfNeeded(headers: metadataHeaders, in: &metadataDoc)
        XLSXWorkbookKit.ensureHeaderIfNeeded(headers: numericHeaders, in: &numericDoc)

        let headerMap = XLSXWorkbookKit.headerColumnMap(in: sampleDoc, sharedStrings: workbook.sharedStrings)

        var metadataSuccess = 0
        var metadataFailed = 0

        for item in metadataWrites {
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let col = headerMap[key] else {
                metadataFailed += 1
                XLSXWorkbookKit.appendLogRow(
                    values: [
                        timestamp,
                        updatedSample.id,
                        updatedSample.batchId,
                        sampleSheet,
                        "\(sampleRow)",
                        key,
                        item.oldValue ?? "",
                        item.newValue ?? "",
                        "failed",
                        "Column not found: \(key)"
                    ],
                    in: &metadataDoc
                )
                continue
            }

            XLSXWorkbookKit.setCellValue(doc: &sampleDoc, row: sampleRow, column: col, value: item.newValue ?? "")
            metadataSuccess += 1
            XLSXWorkbookKit.appendLogRow(
                values: [
                    timestamp,
                        updatedSample.id,
                        updatedSample.batchId,
                        sampleSheet,
                        "\(sampleRow)",
                        key,
                        item.oldValue ?? "",
                        item.newValue ?? "",
                        "success",
                    ""
                ],
                in: &metadataDoc
            )
        }

        for item in numericWrites {
            XLSXWorkbookKit.appendLogRow(
                values: [
                    timestamp,
                    updatedSample.id,
                    updatedSample.batchId,
                    sampleSheet,
                    "\(sampleRow)",
                    item.key,
                    item.oldValue ?? "",
                    item.newValue ?? "",
                    "pending",
                    "",
                    ""
                ],
                in: &numericDoc
            )
        }

        try wrap { try XLSXWorkbookKit.saveXML(sampleDoc, to: workDir.appending(path: samplePath)) }
        try wrap { try XLSXWorkbookKit.saveXML(metadataDoc, to: workDir.appending(path: metadataPath)) }
        try wrap { try XLSXWorkbookKit.saveXML(numericDoc, to: workDir.appending(path: numericPath)) }
        try wrap { try XLSXWorkbookKit.saveWorkbook(workbook, in: workDir) }

        _ = try wrap {
            try XLSXWorkbookKit.commitTransaction(workDir: workDir, sourceURL: registrySourceURL) { candidateURL in
                // Reparse-validate: the candidate must at minimum open as a
                // well-formed workbook again before it's allowed to replace
                // the source. Domain-specific value checks are the growth
                // mutation path's concern (Phase 5A) — this path only ever
                // touches cells it just wrote, addressed by header lookup.
                _ = try XLSXWorkbookKit.loadWorkbook(in: try XLSXWorkbookKit.prepareWorkingDirectory(for: candidateURL))
            }
        }

        return LibraryRegistrySourceSyncResult(
            metadataWrittenCount: metadataSuccess,
            metadataFailedCount: metadataFailed,
            manualLoggedCount: numericWrites.count,
            metadataLogSheetName: Self.metadataSheet,
            manualLogSheetName: Self.numericSheet
        )
    }

    func loadNumericLogEntries(registrySourceURL: URL) throws -> [LibraryManualUpdateLogEntry] {
        guard fileManager.fileExists(atPath: registrySourceURL.path) else {
            throw SyncError.missingFile(path: registrySourceURL.path)
        }
        let workDir = try wrap { try XLSXWorkbookKit.prepareWorkingDirectory(for: registrySourceURL) }
        defer { try? fileManager.removeItem(at: workDir) }
        let workbook = try wrap { try XLSXWorkbookKit.loadWorkbook(in: workDir) }
        guard let sheetPath = try? XLSXWorkbookKit.worksheetPath(named: Self.numericSheet, workbook: workbook) else {
            return []
        }
        let doc = try wrap { try XLSXWorkbookKit.loadXML(at: workDir.appending(path: sheetPath)) }
        let rows = XLSXWorkbookKit.dataRows(in: doc)
        let headerMap = XLSXWorkbookKit.headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)
        var entries: [LibraryManualUpdateLogEntry] = []
        let formatter = ISO8601DateFormatter()

        for row in rows {
            let map = XLSXWorkbookKit.rowValueMap(row: row, headerMap: headerMap, sharedStrings: workbook.sharedStrings)
            guard let sampleId = XLSXWorkbookKit.nonEmpty(map["sample_id"]) else { continue }
            let rowIndex = XLSXWorkbookKit.rowNumber(of: row) ?? 0
            let statusRaw = (XLSXWorkbookKit.nonEmpty(map["status"]) ?? "pending").lowercased()
            let status: LibraryManualLogStatus = statusRaw == "applied" ? .done : (LibraryManualLogStatus(rawValue: statusRaw) ?? .pending)
            entries.append(
                LibraryManualUpdateLogEntry(
                    rowIndex: rowIndex,
                    timestamp: map["timestamp"].flatMap { formatter.date(from: $0) },
                    sampleId: sampleId,
                    batchId: map["batch_id"] ?? "",
                    sheetName: map["sheet_name"] ?? "",
                    rowNumber: Int(map["row_number"] ?? "") ?? 0,
                    fieldType: "numeric",
                    fieldKey: map["tag_key"] ?? "",
                    oldValue: XLSXWorkbookKit.nonEmpty(map["old_value"]),
                    newValue: XLSXWorkbookKit.nonEmpty(map["new_value"]),
                    status: status,
                    statusChangedAt: map["status_changed_at"].flatMap { formatter.date(from: $0) },
                    statusChangedBy: XLSXWorkbookKit.nonEmpty(map["status_changed_by"])
                )
            )
        }

        return entries.sorted {
            let l = $0.timestamp ?? .distantPast
            let r = $1.timestamp ?? .distantPast
            if l == r { return $0.rowIndex > $1.rowIndex }
            return l > r
        }
    }

    func updateNumericLogStatus(
        registrySourceURL: URL,
        rowIndex: Int,
        status: LibraryManualLogStatus,
        statusChangedBy: String
    ) throws {
        guard fileManager.fileExists(atPath: registrySourceURL.path) else {
            throw SyncError.missingFile(path: registrySourceURL.path)
        }
        let workDir = try wrap { try XLSXWorkbookKit.prepareWorkingDirectory(for: registrySourceURL) }
        defer { try? fileManager.removeItem(at: workDir) }
        let workbook = try wrap { try XLSXWorkbookKit.loadWorkbook(in: workDir) }
        let sheetPath = try wrap { try XLSXWorkbookKit.worksheetPath(named: Self.numericSheet, workbook: workbook) }
        var doc = try wrap { try XLSXWorkbookKit.loadXML(at: workDir.appending(path: sheetPath)) }
        let map = XLSXWorkbookKit.headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)

        guard let statusCol = map["status"],
              let changedAtCol = map["status_changed_at"],
              let changedByCol = map["status_changed_by"] else {
            throw SyncError.invalidWorkbook("Numeric log sheet headers are incomplete.")
        }

        let now = ISO8601DateFormatter().string(from: .now)
        XLSXWorkbookKit.setCellValue(doc: &doc, row: rowIndex, column: statusCol, value: status.rawValue)
        XLSXWorkbookKit.setCellValue(doc: &doc, row: rowIndex, column: changedAtCol, value: now)
        XLSXWorkbookKit.setCellValue(doc: &doc, row: rowIndex, column: changedByCol, value: statusChangedBy)

        try wrap { try XLSXWorkbookKit.saveXML(doc, to: workDir.appending(path: sheetPath)) }
        _ = try wrap {
            try XLSXWorkbookKit.commitTransaction(workDir: workDir, sourceURL: registrySourceURL) { candidateURL in
                _ = try XLSXWorkbookKit.loadWorkbook(in: try XLSXWorkbookKit.prepareWorkingDirectory(for: candidateURL))
            }
        }
    }

    func loadMetadataLogEntries(registrySourceURL: URL) throws -> [LibraryMetadataSyncLogEntry] {
        guard fileManager.fileExists(atPath: registrySourceURL.path) else {
            throw SyncError.missingFile(path: registrySourceURL.path)
        }
        let workDir = try wrap { try XLSXWorkbookKit.prepareWorkingDirectory(for: registrySourceURL) }
        defer { try? fileManager.removeItem(at: workDir) }
        let workbook = try wrap { try XLSXWorkbookKit.loadWorkbook(in: workDir) }
        guard let sheetPath = try? XLSXWorkbookKit.worksheetPath(named: Self.metadataSheet, workbook: workbook) else {
            return []
        }
        let doc = try wrap { try XLSXWorkbookKit.loadXML(at: workDir.appending(path: sheetPath)) }
        let rows = XLSXWorkbookKit.dataRows(in: doc)
        let headerMap = XLSXWorkbookKit.headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)
        let formatter = ISO8601DateFormatter()

        var entries: [LibraryMetadataSyncLogEntry] = []
        for row in rows {
            let map = XLSXWorkbookKit.rowValueMap(row: row, headerMap: headerMap, sharedStrings: workbook.sharedStrings)
            guard let sampleId = XLSXWorkbookKit.nonEmpty(map["sample_id"]) else { continue }
            let rowIndex = XLSXWorkbookKit.rowNumber(of: row) ?? 0
            entries.append(
                LibraryMetadataSyncLogEntry(
                    rowIndex: rowIndex,
                    timestamp: map["timestamp"].flatMap { formatter.date(from: $0) },
                    sampleId: sampleId,
                    batchId: map["batch_id"] ?? "",
                    sheetName: map["sheet_name"] ?? "",
                    rowNumber: Int(map["row_number"] ?? "") ?? 0,
                    columnName: map["column_name"] ?? "",
                    oldValue: XLSXWorkbookKit.nonEmpty(map["old_value"]),
                    newValue: XLSXWorkbookKit.nonEmpty(map["new_value"]),
                    writeResult: map["write_result"] ?? "",
                    errorMessage: XLSXWorkbookKit.nonEmpty(map["error_message"])
                )
            )
        }

        return entries.sorted {
            let l = $0.timestamp ?? .distantPast
            let r = $1.timestamp ?? .distantPast
            if l == r { return $0.rowIndex > $1.rowIndex }
            return l > r
        }
    }

    /// Translates a `XLSXWorkbookKitError` (and any other thrown error) from
    /// the shared kit into this service's own `SyncError` so callers keep
    /// seeing the error surface they already handle.
    private func wrap<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as XLSXWorkbookKitError {
            switch error {
            case let .missingFile(path): throw SyncError.missingFile(path: path)
            case let .unzipFailed(message): throw SyncError.unzipFailed(message)
            case let .zipFailed(message): throw SyncError.zipFailed(message)
            case let .invalidWorkbook(message): throw SyncError.invalidWorkbook(message)
            case .backupFailed, .validationFailed, .replaceFailed:
                throw SyncError.transactionFailed(error.errorDescription ?? String(describing: error))
            }
        }
    }
}
