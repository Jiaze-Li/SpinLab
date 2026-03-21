import Foundation

final class LibraryXLSXSyncService {
    enum SyncError: LocalizedError {
        case missingFile(path: String)
        case unzipFailed(String)
        case zipFailed(String)
        case invalidWorkbook(String)
        case missingSampleLocation(sampleId: String)

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

        if metadataWrites.isEmpty, numericWrites.isEmpty {
            return LibraryRegistrySourceSyncResult(
                metadataWrittenCount: 0,
                metadataFailedCount: 0,
                manualLoggedCount: 0,
                metadataLogSheetName: Self.metadataSheet,
                manualLogSheetName: Self.numericSheet
            )
        }

        let workDir = try prepareWorkingDirectory(for: registrySourceURL)
        defer { try? fileManager.removeItem(at: workDir) }

        var workbook = try loadWorkbook(in: workDir)
        let timestamp = ISO8601DateFormatter().string(from: .now)

        let metadataPath = try ensureSheet(named: Self.metadataSheet, in: &workbook, under: workDir)
        let numericPath = try ensureSheet(named: Self.numericSheet, in: &workbook, under: workDir)
        let samplePath = try worksheetPath(named: sampleSheet, workbook: workbook)

        var metadataDoc = try loadXML(at: workDir.appending(path: metadataPath))
        var numericDoc = try loadXML(at: workDir.appending(path: numericPath))
        var sampleDoc = try loadXML(at: workDir.appending(path: samplePath))

        ensureHeaderIfNeeded(headers: metadataHeaders, in: &metadataDoc)
        ensureHeaderIfNeeded(headers: numericHeaders, in: &numericDoc)

        let headerMap = headerColumnMap(in: sampleDoc, sharedStrings: workbook.sharedStrings)

        var metadataSuccess = 0
        var metadataFailed = 0

        for item in metadataWrites {
            guard let col = headerMap[item.key] else {
                metadataFailed += 1
                appendLogRow(
                    values: [
                        timestamp,
                        updatedSample.id,
                        updatedSample.batchId,
                        sampleSheet,
                        "\(sampleRow)",
                        item.key,
                        item.oldValue ?? "",
                        item.newValue ?? "",
                        "failed",
                        "Column not found: \(item.key)"
                    ],
                    in: &metadataDoc
                )
                continue
            }

            setCellValue(doc: &sampleDoc, row: sampleRow, column: col, value: item.newValue ?? "")
            metadataSuccess += 1
            appendLogRow(
                values: [
                    timestamp,
                    updatedSample.id,
                    updatedSample.batchId,
                    sampleSheet,
                    "\(sampleRow)",
                    item.key,
                    item.oldValue ?? "",
                    item.newValue ?? "",
                    "success",
                    ""
                ],
                in: &metadataDoc
            )
        }

        for item in numericWrites {
            appendLogRow(
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

        try saveXML(sampleDoc, to: workDir.appending(path: samplePath))
        try saveXML(metadataDoc, to: workDir.appending(path: metadataPath))
        try saveXML(numericDoc, to: workDir.appending(path: numericPath))
        try saveWorkbook(workbook, in: workDir)

        try backupAndReplaceXLSX(workDir: workDir, sourceURL: registrySourceURL)

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
        let workDir = try prepareWorkingDirectory(for: registrySourceURL)
        defer { try? fileManager.removeItem(at: workDir) }
        let workbook = try loadWorkbook(in: workDir)
        guard let sheetPath = try? worksheetPath(named: Self.numericSheet, workbook: workbook) else {
            return []
        }
        let doc = try loadXML(at: workDir.appending(path: sheetPath))
        let rows = dataRows(in: doc)
        let headerMap = headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)
        var entries: [LibraryManualUpdateLogEntry] = []
        let formatter = ISO8601DateFormatter()

        for row in rows {
            let map = rowValueMap(row: row, headerMap: headerMap, sharedStrings: workbook.sharedStrings)
            guard let sampleId = nonEmpty(map["sample_id"]) else { continue }
            let rowIndex = Int(row.attribute(forName: "r")?.stringValue ?? "") ?? 0
            let statusRaw = (nonEmpty(map["status"]) ?? "pending").lowercased()
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
                    oldValue: nonEmpty(map["old_value"]),
                    newValue: nonEmpty(map["new_value"]),
                    status: status,
                    statusChangedAt: map["status_changed_at"].flatMap { formatter.date(from: $0) },
                    statusChangedBy: nonEmpty(map["status_changed_by"])
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
        let workDir = try prepareWorkingDirectory(for: registrySourceURL)
        defer { try? fileManager.removeItem(at: workDir) }
        let workbook = try loadWorkbook(in: workDir)
        let sheetPath = try worksheetPath(named: Self.numericSheet, workbook: workbook)
        var doc = try loadXML(at: workDir.appending(path: sheetPath))
        let map = headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)

        guard let statusCol = map["status"],
              let changedAtCol = map["status_changed_at"],
              let changedByCol = map["status_changed_by"] else {
            throw SyncError.invalidWorkbook("Numeric log sheet headers are incomplete.")
        }

        let now = ISO8601DateFormatter().string(from: .now)
        setCellValue(doc: &doc, row: rowIndex, column: statusCol, value: status.rawValue)
        setCellValue(doc: &doc, row: rowIndex, column: changedAtCol, value: now)
        setCellValue(doc: &doc, row: rowIndex, column: changedByCol, value: statusChangedBy)

        try saveXML(doc, to: workDir.appending(path: sheetPath))
        try backupAndReplaceXLSX(workDir: workDir, sourceURL: registrySourceURL)
    }

    func loadMetadataLogEntries(registrySourceURL: URL) throws -> [LibraryMetadataSyncLogEntry] {
        guard fileManager.fileExists(atPath: registrySourceURL.path) else {
            throw SyncError.missingFile(path: registrySourceURL.path)
        }
        let workDir = try prepareWorkingDirectory(for: registrySourceURL)
        defer { try? fileManager.removeItem(at: workDir) }
        let workbook = try loadWorkbook(in: workDir)
        guard let sheetPath = try? worksheetPath(named: Self.metadataSheet, workbook: workbook) else {
            return []
        }
        let doc = try loadXML(at: workDir.appending(path: sheetPath))
        let rows = dataRows(in: doc)
        let headerMap = headerColumnMap(in: doc, sharedStrings: workbook.sharedStrings)
        let formatter = ISO8601DateFormatter()

        var entries: [LibraryMetadataSyncLogEntry] = []
        for row in rows {
            let map = rowValueMap(row: row, headerMap: headerMap, sharedStrings: workbook.sharedStrings)
            guard let sampleId = nonEmpty(map["sample_id"]) else { continue }
            let rowIndex = Int(row.attribute(forName: "r")?.stringValue ?? "") ?? 0
            entries.append(
                LibraryMetadataSyncLogEntry(
                    rowIndex: rowIndex,
                    timestamp: map["timestamp"].flatMap { formatter.date(from: $0) },
                    sampleId: sampleId,
                    batchId: map["batch_id"] ?? "",
                    sheetName: map["sheet_name"] ?? "",
                    rowNumber: Int(map["row_number"] ?? "") ?? 0,
                    columnName: map["column_name"] ?? "",
                    oldValue: nonEmpty(map["old_value"]),
                    newValue: nonEmpty(map["new_value"]),
                    writeResult: map["write_result"] ?? "",
                    errorMessage: nonEmpty(map["error_message"])
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

    private struct WorkbookContext {
        var workbookDoc: XMLDocument
        var workbookRelsDoc: XMLDocument
        var contentTypesDoc: XMLDocument
        var sharedStrings: [String]
    }

    private func prepareWorkingDirectory(for sourceURL: URL) throws -> URL {
        let dir = fileManager.temporaryDirectory.appending(path: "spinlab_xlsx_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let output = try runProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", sourceURL.path, "-d", dir.path],
            currentDirectory: nil
        )
        guard output.status == 0 else {
            throw SyncError.unzipFailed(output.stderr)
        }
        return dir
    }

    private func backupAndReplaceXLSX(workDir: URL, sourceURL: URL) throws {
        let backupDir = sourceURL.deletingLastPathComponent().appending(path: "backups", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let timestamp = DateFormatter.spinlabBackup.string(from: .now)
        let backupURL = backupDir.appending(path: "registry_source_backup_\(timestamp).xlsx")
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        try? fileManager.copyItem(at: sourceURL, to: backupURL)

        let rewrittenURL = workDir.appending(path: "rewritten.xlsx")
        let zipOutput = try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-q", "-r", rewrittenURL.path, "."],
            currentDirectory: workDir
        )
        guard zipOutput.status == 0, fileManager.fileExists(atPath: rewrittenURL.path) else {
            throw SyncError.zipFailed(zipOutput.stderr)
        }

        try fileManager.removeItem(at: sourceURL)
        try fileManager.moveItem(at: rewrittenURL, to: sourceURL)
    }

    private func loadWorkbook(in root: URL) throws -> WorkbookContext {
        let workbookURL = root.appending(path: "xl/workbook.xml")
        let relsURL = root.appending(path: "xl/_rels/workbook.xml.rels")
        let contentTypesURL = root.appending(path: "[Content_Types].xml")

        guard let workbookDoc = try? XMLDocument(contentsOf: workbookURL, options: []),
              let relsDoc = try? XMLDocument(contentsOf: relsURL, options: []),
              let contentDoc = try? XMLDocument(contentsOf: contentTypesURL, options: []) else {
            throw SyncError.invalidWorkbook("Failed to read workbook metadata.")
        }

        let sharedStringsURL = root.appending(path: "xl/sharedStrings.xml")
        var shared: [String] = []
        if let sharedDoc = try? XMLDocument(contentsOf: sharedStringsURL, options: []),
           let nodes = try? sharedDoc.nodes(forXPath: "//*[local-name()='si']") {
            shared = nodes.compactMap { node in
                guard let el = node as? XMLElement else { return nil }
                return Self.textInSI(el)
            }
        }

        return WorkbookContext(
            workbookDoc: workbookDoc,
            workbookRelsDoc: relsDoc,
            contentTypesDoc: contentDoc,
            sharedStrings: shared
        )
    }

    private func saveWorkbook(_ workbook: WorkbookContext, in root: URL) throws {
        try saveXML(workbook.workbookDoc, to: root.appending(path: "xl/workbook.xml"))
        try saveXML(workbook.workbookRelsDoc, to: root.appending(path: "xl/_rels/workbook.xml.rels"))
        try saveXML(workbook.contentTypesDoc, to: root.appending(path: "[Content_Types].xml"))
    }

    private func worksheetPath(named sheetName: String, workbook: WorkbookContext) throws -> String {
        let sheetNodes = try workbook.workbookDoc.nodes(forXPath: "/*[local-name()='workbook']/*[local-name()='sheets']/*[local-name()='sheet']")
        for node in sheetNodes {
            guard let sheet = node as? XMLElement,
                  sheet.attribute(forName: "name")?.stringValue == sheetName else { continue }
            let relID = sheet.attribute(forName: "r:id")?.stringValue
                ?? sheet.attribute(forName: "id")?.stringValue
                ?? sheet.attributes?.first(where: { ($0.name ?? "").hasSuffix(":id") })?.stringValue
            guard let relID else { continue }
            let relNodes = try workbook.workbookRelsDoc.nodes(forXPath: "/*[local-name()='Relationships']/*[local-name()='Relationship']")
            for relNode in relNodes {
                guard let rel = relNode as? XMLElement,
                      rel.attribute(forName: "Id")?.stringValue == relID,
                      let target = rel.attribute(forName: "Target")?.stringValue else { continue }
                return target.hasPrefix("/") ? String(target.dropFirst()) : "xl/\(target)"
            }
        }
        throw SyncError.invalidWorkbook("Sheet not found in xlsx: \(sheetName)")
    }

    private func ensureSheet(named sheetName: String, in workbook: inout WorkbookContext, under root: URL) throws -> String {
        if let path = try? worksheetPath(named: sheetName, workbook: workbook) {
            return path
        }

        let relNodes = try workbook.workbookRelsDoc.nodes(forXPath: "/*[local-name()='Relationships']/*[local-name()='Relationship']")
        let existingRelNums = relNodes.compactMap { node -> Int? in
            guard let el = node as? XMLElement,
                  let id = el.attribute(forName: "Id")?.stringValue,
                  id.hasPrefix("rId") else { return nil }
            return Int(id.dropFirst(3))
        }
        let nextRel = (existingRelNums.max() ?? 0) + 1
        let relID = "rId\(nextRel)"

        let sheetNodes = try workbook.workbookDoc.nodes(forXPath: "/*[local-name()='workbook']/*[local-name()='sheets']/*[local-name()='sheet']")
        let nextSheetID = (sheetNodes.compactMap { ($0 as? XMLElement)?.attribute(forName: "sheetId")?.stringValue }.compactMap(Int.init).max() ?? 0) + 1

        let worksheetDir = root.appending(path: "xl/worksheets", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: worksheetDir, withIntermediateDirectories: true)
        let existingSheetNumbers = (try? fileManager.contentsOfDirectory(at: worksheetDir, includingPropertiesForKeys: nil))?.compactMap { url -> Int? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("sheet") else { return nil }
            return Int(name.dropFirst("sheet".count))
        } ?? []
        let nextSheetNum = (existingSheetNumbers.max() ?? 0) + 1
        let worksheetFile = "sheet\(nextSheetNum).xml"
        let worksheetPath = "xl/worksheets/\(worksheetFile)"

        let newSheetXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"
        try newSheetXML.data(using: .utf8)?.write(to: root.appending(path: worksheetPath), options: .atomic)

        if let relRoot = try workbook.workbookRelsDoc.nodes(forXPath: "/*[local-name()='Relationships']").first as? XMLElement {
            let relationship = XMLElement(name: "Relationship")
            relationship.addAttribute(XMLNode.attribute(withName: "Id", stringValue: relID) as! XMLNode)
            relationship.addAttribute(XMLNode.attribute(withName: "Type", stringValue: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet") as! XMLNode)
            relationship.addAttribute(XMLNode.attribute(withName: "Target", stringValue: "worksheets/\(worksheetFile)") as! XMLNode)
            relRoot.addChild(relationship)
        }

        if let sheetsRoot = try workbook.workbookDoc.nodes(forXPath: "/*[local-name()='workbook']/*[local-name()='sheets']").first as? XMLElement {
            let sheet = XMLElement(name: "sheet")
            sheet.addAttribute(XMLNode.attribute(withName: "name", stringValue: sheetName) as! XMLNode)
            sheet.addAttribute(XMLNode.attribute(withName: "sheetId", stringValue: "\(nextSheetID)") as! XMLNode)
            sheet.addAttribute(XMLNode.attribute(withName: "r:id", stringValue: relID) as! XMLNode)
            sheetsRoot.addChild(sheet)
        }

        if let typesRoot = try workbook.contentTypesDoc.nodes(forXPath: "/*[local-name()='Types']").first as? XMLElement {
            let exists = (try? workbook.contentTypesDoc.nodes(forXPath: "/*[local-name()='Types']/*[local-name()='Override' and @PartName='/\(worksheetPath)']"))?.isEmpty == false
            if !exists {
                let override = XMLElement(name: "Override")
                override.addAttribute(XMLNode.attribute(withName: "PartName", stringValue: "/\(worksheetPath)") as! XMLNode)
                override.addAttribute(XMLNode.attribute(withName: "ContentType", stringValue: "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml") as! XMLNode)
                typesRoot.addChild(override)
            }
        }

        return worksheetPath
    }

    private func ensureHeaderIfNeeded(headers: [String], in doc: inout XMLDocument) {
        let map = headerColumnMap(in: doc, sharedStrings: [])
        if !map.isEmpty { return }
        for (index, header) in headers.enumerated() {
            let col = Self.columnLetters(from: index + 1)
            setCellValue(doc: &doc, row: 1, column: col, value: header)
        }
    }

    private func headerColumnMap(in doc: XMLDocument, sharedStrings: [String]) -> [String: String] {
        guard let row = try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row' and @r='1']").first as? XMLElement else {
            return [:]
        }
        var map: [String: String] = [:]
        for case let cell as XMLElement in (row.children ?? []) where cell.name == "c" {
            guard let ref = cell.attribute(forName: "r")?.stringValue,
                  let col = Self.columnPart(of: ref),
                  let value = readCellValue(cell: cell, sharedStrings: sharedStrings),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            map[value] = col
        }
        return map
    }

    private func dataRows(in doc: XMLDocument) -> [XMLElement] {
        guard let rows = try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']") else {
            return []
        }
        return rows.compactMap { $0 as? XMLElement }.filter { ($0.attribute(forName: "r")?.stringValue.flatMap(Int.init) ?? 0) >= 2 }
    }

    private func rowValueMap(row: XMLElement, headerMap: [String: String], sharedStrings: [String]) -> [String: String] {
        var valuesByColumn: [String: String] = [:]
        for case let cell as XMLElement in (row.children ?? []) where cell.name == "c" {
            guard let ref = cell.attribute(forName: "r")?.stringValue,
                  let col = Self.columnPart(of: ref),
                  let value = readCellValue(cell: cell, sharedStrings: sharedStrings) else {
                continue
            }
            valuesByColumn[col] = value
        }
        var map: [String: String] = [:]
        for (key, column) in headerMap {
            map[key] = valuesByColumn[column]
        }
        return map
    }

    private func appendLogRow(values: [String], in doc: inout XMLDocument) {
        let maxRow = (try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']").compactMap { ($0 as? XMLElement)?.attribute(forName: "r")?.stringValue }.compactMap(Int.init).max()) ?? 1
        let nextRow = max(maxRow + 1, 2)
        for (index, value) in values.enumerated() {
            let col = Self.columnLetters(from: index + 1)
            setCellValue(doc: &doc, row: nextRow, column: col, value: value)
        }
    }

    private func setCellValue(doc: inout XMLDocument, row: Int, column: String, value: String) {
        let sheetData = ensureSheetData(in: &doc)
        let rowElement = ensureRow(in: sheetData, row: row)
        let ref = "\(column)\(row)"
        let cellElement = ensureCell(in: rowElement, ref: ref)

        cellElement.setAttributesWith([
            "r": ref,
            "t": "inlineStr"
        ])
        for child in cellElement.children ?? [] {
            child.detach()
        }
        let isNode = XMLElement(name: "is")
        let tNode = XMLElement(name: "t", stringValue: value)
        isNode.addChild(tNode)
        cellElement.addChild(isNode)
    }

    private func ensureSheetData(in doc: inout XMLDocument) -> XMLElement {
        if let existing = try? doc.nodes(forXPath: "//*[local-name()='sheetData']").first as? XMLElement {
            return existing
        }
        let root = doc.rootElement() ?? XMLElement(name: "worksheet")
        if doc.rootElement() == nil {
            doc.setRootElement(root)
        }
        let sheetData = XMLElement(name: "sheetData")
        root.addChild(sheetData)
        return sheetData
    }

    private func ensureRow(in sheetData: XMLElement, row: Int) -> XMLElement {
        for case let existing as XMLElement in (sheetData.children ?? []) where existing.name == "row" {
            if existing.attribute(forName: "r")?.stringValue == "\(row)" {
                return existing
            }
        }
        let rowEl = XMLElement(name: "row")
        rowEl.addAttribute(XMLNode.attribute(withName: "r", stringValue: "\(row)") as! XMLNode)
        sheetData.addChild(rowEl)
        return rowEl
    }

    private func ensureCell(in row: XMLElement, ref: String) -> XMLElement {
        for case let existing as XMLElement in (row.children ?? []) where existing.name == "c" {
            if existing.attribute(forName: "r")?.stringValue == ref {
                return existing
            }
        }
        let cell = XMLElement(name: "c")
        cell.addAttribute(XMLNode.attribute(withName: "r", stringValue: ref) as! XMLNode)
        row.addChild(cell)
        return cell
    }

    private func loadXML(at url: URL) throws -> XMLDocument {
        guard let doc = try? XMLDocument(contentsOf: url, options: [.nodePreserveAll]) else {
            throw SyncError.invalidWorkbook("Unable to read XML at \(url.path)")
        }
        return doc
    }

    private func saveXML(_ doc: XMLDocument, to url: URL) throws {
        let data = doc.xmlData(options: [.nodePrettyPrint])
        try data.write(to: url, options: .atomic)
    }

    private func runProcess(executable: String, arguments: [String], currentDirectory: URL?) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }

    private static func textInSI(_ si: XMLElement) -> String? {
        if let t = try? si.nodes(forXPath: "./*[local-name()='t']").first as? XMLElement {
            return t.stringValue
        }
        if let nodes = try? si.nodes(forXPath: ".//*[local-name()='t']") as? [XMLElement] {
            return nodes.compactMap(\.stringValue).joined()
        }
        return nil
    }

    private static func columnPart(of cellRef: String) -> String? {
        let letters = cellRef.prefix { $0.isLetter }
        return letters.isEmpty ? nil : String(letters)
    }

    private static func columnLetters(from index: Int) -> String {
        var value = index
        var letters = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            value = (value - 1) / 26
        }
        return letters
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readCellValue(cell: XMLElement, sharedStrings: [String]) -> String? {
        let cellType = cell.attribute(forName: "t")?.stringValue
        if cellType == "s",
           let vNode = try? cell.nodes(forXPath: "./*[local-name()='v']").first as? XMLElement,
           let raw = vNode.stringValue,
           let index = Int(raw),
           sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        if cellType == "inlineStr" {
            if let tNode = try? cell.nodes(forXPath: "./*[local-name()='is']/*[local-name()='t']").first as? XMLElement {
                return tNode.stringValue
            }
        }
        if let vNode = try? cell.nodes(forXPath: "./*[local-name()='v']").first as? XMLElement {
            return vNode.stringValue
        }
        return nil
    }
}

private extension DateFormatter {
    static let spinlabBackup: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
