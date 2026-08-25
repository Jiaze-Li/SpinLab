import CryptoKit
import Foundation

/// Shared low-level OOXML (.xlsx) working-copy primitives, used by both
/// `LibraryXLSXSyncService` (Sample-edit → existing Registry row) and
/// `RegistryGrowthMutationService` (Obsidian growth → new/reserved Registry
/// row). Neither caller's mutation *semantics* (ownership guard, dedup,
/// routing) live here — this file only knows how to unzip/parse/edit/
/// rezip/validate/replace a workbook safely.
enum XLSXWorkbookKitError: LocalizedError {
    case missingFile(path: String)
    case unzipFailed(String)
    case zipFailed(String)
    case invalidWorkbook(String)
    case backupFailed(String)
    case validationFailed(String)
    case replaceFailed(String, backupPath: String)
    /// The live source file's content fingerprint no longer matches the one
    /// captured when the transaction began — a manual edit or cloud-sync
    /// change landed in the TOCTOU window between validation and the atomic
    /// replace. The candidate is discarded and the source is never touched.
    case staleFingerprint(expected: String, current: String)

    var errorDescription: String? {
        switch self {
        case let .missingFile(path):
            return "Registry source file does not exist: \(path)"
        case let .unzipFailed(message):
            return "xlsx unzip failed (\(message))"
        case let .zipFailed(message):
            return "xlsx zip failed (\(message))"
        case let .invalidWorkbook(message):
            return "Invalid workbook: \(message)"
        case let .backupFailed(message):
            return "Backup of original workbook failed, aborting before any mutation could be applied: \(message)"
        case let .validationFailed(message):
            return "Candidate workbook failed pre-replace validation, original left untouched: \(message)"
        case let .replaceFailed(message, backupPath):
            return "Atomic replace failed (\(message)). Original should be intact; a backup also exists at \(backupPath)."
        case let .staleFingerprint(expected, current):
            return "Source file changed since the transaction began (expected fingerprint \(expected), found \(current)); candidate discarded, original left untouched."
        }
    }
}

/// Parsed workbook-level metadata (sheet list, rels, content types, shared
/// strings) for a working copy rooted at some unzipped directory.
struct XLSXWorkbookContext {
    var workbookDoc: XMLDocument
    var workbookRelsDoc: XMLDocument
    var contentTypesDoc: XMLDocument
    var sharedStrings: [String]
}

/// Stateless helpers operating on an unzipped xlsx working directory.
enum XLSXWorkbookKit {
    static let fileManager = FileManager.default

    // MARK: - Working copy lifecycle

    static func prepareWorkingDirectory(for sourceURL: URL) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw XLSXWorkbookKitError.missingFile(path: sourceURL.path)
        }
        let dir = fileManager.temporaryDirectory.appending(path: "spinlab_xlsx_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let output = try runProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-qq", sourceURL.path, "-d", dir.path],
            currentDirectory: nil
        )
        guard output.status == 0 else {
            throw XLSXWorkbookKitError.unzipFailed(output.stderr)
        }
        return dir
    }

    static func loadWorkbook(in root: URL) throws -> XLSXWorkbookContext {
        let workbookURL = root.appending(path: "xl/workbook.xml")
        let relsURL = root.appending(path: "xl/_rels/workbook.xml.rels")
        let contentTypesURL = root.appending(path: "[Content_Types].xml")

        guard let workbookDoc = try? XMLDocument(contentsOf: workbookURL, options: []),
              let relsDoc = try? XMLDocument(contentsOf: relsURL, options: []),
              let contentDoc = try? XMLDocument(contentsOf: contentTypesURL, options: []) else {
            throw XLSXWorkbookKitError.invalidWorkbook("Failed to read workbook metadata.")
        }

        let sharedStringsURL = root.appending(path: "xl/sharedStrings.xml")
        var shared: [String] = []
        if let sharedDoc = try? XMLDocument(contentsOf: sharedStringsURL, options: []),
           let nodes = try? sharedDoc.nodes(forXPath: "//*[local-name()='si']") {
            shared = nodes.compactMap { node in
                guard let el = node as? XMLElement else { return nil }
                return textInSI(el)
            }
        }

        return XLSXWorkbookContext(
            workbookDoc: workbookDoc,
            workbookRelsDoc: relsDoc,
            contentTypesDoc: contentDoc,
            sharedStrings: shared
        )
    }

    static func saveWorkbook(_ workbook: XLSXWorkbookContext, in root: URL) throws {
        try saveXML(workbook.workbookDoc, to: root.appending(path: "xl/workbook.xml"))
        try saveXML(workbook.workbookRelsDoc, to: root.appending(path: "xl/_rels/workbook.xml.rels"))
        try saveXML(workbook.contentTypesDoc, to: root.appending(path: "[Content_Types].xml"))
    }

    static func worksheetPath(named sheetName: String, workbook: XLSXWorkbookContext) throws -> String {
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
        throw XLSXWorkbookKitError.invalidWorkbook("Sheet not found in xlsx: \(sheetName)")
    }

    /// Ordered sheet names as declared in workbook.xml (used to detect an
    /// unexpected sheet-order change or an unexpected new sheet after
    /// mutation — see candidate validation requirements).
    static func sheetNames(workbook: XLSXWorkbookContext) throws -> [String] {
        let sheetNodes = try workbook.workbookDoc.nodes(forXPath: "/*[local-name()='workbook']/*[local-name()='sheets']/*[local-name()='sheet']")
        return sheetNodes.compactMap { ($0 as? XMLElement)?.attribute(forName: "name")?.stringValue }
    }

    static func ensureSheet(named sheetName: String, in workbook: inout XLSXWorkbookContext, under root: URL) throws -> String {
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

    // MARK: - Sheet content access

    static func ensureHeaderIfNeeded(headers: [String], sharedStrings: [String], in doc: inout XMLDocument) {
        let map = headerColumnMap(in: doc, sharedStrings: sharedStrings)
        if !map.isEmpty { return }
        for (index, header) in headers.enumerated() {
            let col = columnLetters(from: index + 1)
            setCellValue(doc: &doc, row: 1, column: col, value: header)
        }
    }

    static func headerColumnMap(in doc: XMLDocument, sharedStrings: [String]) -> [String: String] {
        guard let row = try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row' and @r='1']").first as? XMLElement else {
            return [:]
        }
        var map: [String: String] = [:]
        for case let cell as XMLElement in (row.children ?? []) where cell.name == "c" {
            guard let ref = cell.attribute(forName: "r")?.stringValue,
                  let col = columnPart(of: ref),
                  let value = readCellValue(cell: cell, sharedStrings: sharedStrings),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            map[value.trimmingCharacters(in: .whitespacesAndNewlines)] = col
        }
        return map
    }

    static func dataRows(in doc: XMLDocument) -> [XMLElement] {
        guard let rows = try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']") else {
            return []
        }
        return rows.compactMap { $0 as? XMLElement }.filter { ($0.attribute(forName: "r")?.stringValue.flatMap(Int.init) ?? 0) >= 2 }
    }

    static func rowValueMap(row: XMLElement, headerMap: [String: String], sharedStrings: [String]) -> [String: String] {
        var valuesByColumn: [String: String] = [:]
        for case let cell as XMLElement in (row.children ?? []) where cell.name == "c" {
            guard let ref = cell.attribute(forName: "r")?.stringValue,
                  let col = columnPart(of: ref),
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

    static func rowNumber(of row: XMLElement) -> Int? {
        row.attribute(forName: "r")?.stringValue.flatMap(Int.init)
    }

    /// The style id (`s="..."`) of a cell, if present. Used by the growth
    /// mutation path to clone a template row's per-cell styling.
    static func cellStyleAttribute(row: XMLElement, column: String) -> String? {
        for case let cell as XMLElement in (row.children ?? []) where cell.name == "c" {
            guard let ref = cell.attribute(forName: "r")?.stringValue, columnPart(of: ref) == column else { continue }
            return cell.attribute(forName: "s")?.stringValue
        }
        return nil
    }

    static func rowStyleAttribute(row: XMLElement) -> String? {
        row.attribute(forName: "s")?.stringValue
    }

    // MARK: - Cell mutation (style-preserving)

    /// Writes `value` into the cell at (row, column), preserving that cell's
    /// existing `s` (style) attribute and any other structural attribute
    /// other than the ones this function owns (`r`, `t`). Only the cell's
    /// type/value representation is replaced.
    ///
    /// Fixes a prior bug where `setAttributesWith(["r":..., "t": "inlineStr"])`
    /// wholesale-replaced the cell's attribute set, silently discarding
    /// `s="..."` and corrupting the workbook's visual formatting on every
    /// write. See Phase 5A spec §12.
    static func setCellValue(doc: inout XMLDocument, row: Int, column: String, value: String) {
        let sheetData = ensureSheetData(in: &doc)
        let rowElement = ensureRow(in: sheetData, row: row)
        let ref = "\(column)\(row)"
        let cellElement = ensureCell(in: rowElement, ref: ref)

        let preservedStyle = cellElement.attribute(forName: "s")?.stringValue

        for attribute in (cellElement.attributes ?? []) where attribute.name != "r" && attribute.name != "s" {
            attribute.detach()
        }
        if cellElement.attribute(forName: "r") == nil {
            cellElement.addAttribute(XMLNode.attribute(withName: "r", stringValue: ref) as! XMLNode)
        }
        cellElement.addAttribute(XMLNode.attribute(withName: "t", stringValue: "inlineStr") as! XMLNode)
        if let preservedStyle {
            cellElement.addAttribute(XMLNode.attribute(withName: "s", stringValue: preservedStyle) as! XMLNode)
        }

        for child in cellElement.children ?? [] {
            child.detach()
        }
        let isNode = XMLElement(name: "is")
        let tNode = XMLElement(name: "t", stringValue: value)
        isNode.addChild(tNode)
        cellElement.addChild(isNode)
    }

    /// Sets a cell's style id without touching its value — used to seed a
    /// freshly-appended row's cells with a template row's styling before
    /// `setCellValue` fills in the actual growth values.
    static func setCellStyle(doc: inout XMLDocument, row: Int, column: String, style: String?) {
        let sheetData = ensureSheetData(in: &doc)
        let rowElement = ensureRow(in: sheetData, row: row)
        let ref = "\(column)\(row)"
        let cellElement = ensureCell(in: rowElement, ref: ref)
        guard let style else { return }
        for attribute in (cellElement.attributes ?? []) where attribute.name == "s" {
            attribute.detach()
        }
        cellElement.addAttribute(XMLNode.attribute(withName: "s", stringValue: style) as! XMLNode)
    }

    static func setRowStyle(doc: inout XMLDocument, row: Int, style: String?) {
        let sheetData = ensureSheetData(in: &doc)
        let rowElement = ensureRow(in: sheetData, row: row)
        guard let style else { return }
        for attribute in (rowElement.attributes ?? []) where attribute.name == "s" || attribute.name == "customFormat" {
            attribute.detach()
        }
        rowElement.addAttribute(XMLNode.attribute(withName: "s", stringValue: style) as! XMLNode)
        rowElement.addAttribute(XMLNode.attribute(withName: "customFormat", stringValue: "1") as! XMLNode)
    }

    static func appendLogRow(values: [String], in doc: inout XMLDocument) {
        let maxRow = (try? doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']").compactMap { ($0 as? XMLElement)?.attribute(forName: "r")?.stringValue }.compactMap(Int.init).max()) ?? 1
        let nextRow = max(maxRow + 1, 2)
        for (index, value) in values.enumerated() {
            let col = columnLetters(from: index + 1)
            setCellValue(doc: &doc, row: nextRow, column: col, value: value)
        }
    }

    static func ensureSheetData(in doc: inout XMLDocument) -> XMLElement {
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

    static func ensureRow(in sheetData: XMLElement, row: Int) -> XMLElement {
        for case let existing as XMLElement in (sheetData.children ?? []) where existing.name == "row" {
            if existing.attribute(forName: "r")?.stringValue == "\(row)" {
                return existing
            }
        }
        let rowEl = XMLElement(name: "row")
        rowEl.addAttribute(XMLNode.attribute(withName: "r", stringValue: "\(row)") as! XMLNode)
        // Keep rows in ascending `r` order so downstream readers that assume
        // document order match row order (e.g. "last data row" scans) stay correct.
        let insertionIndex = (sheetData.children ?? []).firstIndex { child in
            guard let el = child as? XMLElement, el.name == "row",
                  let r = el.attribute(forName: "r")?.stringValue.flatMap(Int.init) else { return false }
            return r > row
        }
        if let insertionIndex {
            sheetData.insertChild(rowEl, at: insertionIndex)
        } else {
            sheetData.addChild(rowEl)
        }
        return rowEl
    }

    static func ensureCell(in row: XMLElement, ref: String) -> XMLElement {
        for case let existing as XMLElement in (row.children ?? []) where existing.name == "c" {
            if existing.attribute(forName: "r")?.stringValue == ref {
                return existing
            }
        }
        let cell = XMLElement(name: "c")
        cell.addAttribute(XMLNode.attribute(withName: "r", stringValue: ref) as! XMLNode)
        guard let column = columnPart(of: ref) else {
            row.addChild(cell)
            return cell
        }
        let insertionIndex = (row.children ?? []).firstIndex { child in
            guard let el = child as? XMLElement, el.name == "c",
                  let existingRef = el.attribute(forName: "r")?.stringValue,
                  let existingColumn = columnPart(of: existingRef) else { return false }
            return columnIndex(existingColumn) > columnIndex(column)
        }
        if let insertionIndex {
            row.insertChild(cell, at: insertionIndex)
        } else {
            row.addChild(cell)
        }
        return cell
    }

    // MARK: - XML I/O

    static func loadXML(at url: URL) throws -> XMLDocument {
        guard let doc = try? XMLDocument(contentsOf: url, options: [.nodePreserveAll]) else {
            throw XLSXWorkbookKitError.invalidWorkbook("Unable to read XML at \(url.path)")
        }
        return doc
    }

    static func saveXML(_ doc: XMLDocument, to url: URL) throws {
        let data = doc.xmlData(options: [.nodePrettyPrint])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Process helpers

    static func runProcess(executable: String, arguments: [String], currentDirectory: URL?) throws -> (status: Int32, stderr: String) {
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

    // MARK: - Value / string helpers

    static func textInSI(_ si: XMLElement) -> String? {
        if let t = try? si.nodes(forXPath: "./*[local-name()='t']").first as? XMLElement {
            return t.stringValue
        }
        if let nodes = try? si.nodes(forXPath: ".//*[local-name()='t']") as? [XMLElement] {
            return nodes.compactMap(\.stringValue).joined()
        }
        return nil
    }

    static func columnPart(of cellRef: String) -> String? {
        let letters = cellRef.prefix { $0.isLetter }
        return letters.isEmpty ? nil : String(letters)
    }

    static func columnLetters(from index: Int) -> String {
        var value = index
        var letters = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            value = (value - 1) / 26
        }
        return letters
    }

    static func columnIndex(_ letters: String) -> Int {
        var value = 0
        for scalar in letters.unicodeScalars {
            value = value * 26 + Int(scalar.value) - 64
        }
        return value
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func readCellValue(cell: XMLElement, sharedStrings: [String]) -> String? {
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

    // MARK: - Transaction: validate candidate, backup original, atomic replace

    /// Hardened write-back transaction (Phase 5A spec §16/§17):
    ///
    ///   working copy → zip candidate beside source → validate candidate
    ///   (caller-supplied, e.g. CoreXLSX reparse + structural checks) →
    ///   backup original (must succeed or abort) → atomic same-directory
    ///   replace.
    ///
    /// Invariants:
    ///  - The source file is never removed before the replacement is
    ///    confirmed written (`FileManager.replaceItemAt` handles this;
    ///    unlike the old remove-then-move sequence, an interrupted replace
    ///    leaves the original in place).
    ///  - A backup-copy failure aborts before any candidate validation
    ///    result can matter — the original is never touched.
    ///  - A candidate-validation failure aborts before touching the source
    ///    or writing a backup.
    @discardableResult
    static func commitTransaction(
        workDir: URL,
        sourceURL: URL,
        expectedSourceFingerprint: String? = nil,
        validateCandidate: (URL) throws -> Void
    ) throws -> URL {
        // Staging must happen beside `sourceURL`, not in system temp
        // (`workDir`'s parent) — `replaceItemAt` requires same-volume/
        // same-directory semantics to stay atomic, and a cloud-synced
        // Registry (OneDrive/CloudStorage) needs the candidate to appear
        // under the synced directory for the eventual replace to be seen
        // as an in-place edit rather than a delete+create. Hidden
        // (dot-prefixed) unique name so it never appears as a real sheet
        // to the user or the sync client before it's cleaned up.
        let candidateURL = sourceURL.deletingLastPathComponent()
            .appending(path: ".spinlab-candidate-\(UUID().uuidString).xlsx")
        let zipOutput = try runProcess(
            executable: "/usr/bin/zip",
            arguments: ["-q", "-r", candidateURL.path, "."],
            currentDirectory: workDir
        )
        guard zipOutput.status == 0, fileManager.fileExists(atPath: candidateURL.path) else {
            throw XLSXWorkbookKitError.zipFailed(zipOutput.stderr)
        }
        defer { try? fileManager.removeItem(at: candidateURL) }

        do {
            try validateCandidate(candidateURL)
        } catch {
            throw XLSXWorkbookKitError.validationFailed(String(describing: error))
        }

        let backupURL = try backup(sourceURL: sourceURL)

        // Final TOCTOU guard, immediately before the atomic replace: a
        // manual edit or cloud-sync change could have landed on the live
        // source in the window between whatever fingerprint check the
        // caller already ran (e.g. plan-vs-Registry, before any of this
        // transaction's work started) and this exact moment. Re-reading and
        // re-comparing right here — not trusting the earlier check alone —
        // is the only way to close that window; the backup above is
        // harmless either way since it never touches the live source.
        if let expectedSourceFingerprint {
            let liveFingerprint = try contentFingerprint(of: sourceURL)
            guard liveFingerprint == expectedSourceFingerprint else {
                throw XLSXWorkbookKitError.staleFingerprint(expected: expectedSourceFingerprint, current: liveFingerprint)
            }
        }

        do {
            _ = try fileManager.replaceItemAt(sourceURL, withItemAt: candidateURL)
        } catch {
            throw XLSXWorkbookKitError.replaceFailed(String(describing: error), backupPath: backupURL.path)
        }

        return backupURL
    }

    /// Copies `sourceURL` into a timestamped backup file beside it. Throws
    /// (does not swallow) on failure — a failed backup must abort the whole
    /// transaction, never proceed as if nothing needed protecting.
    @discardableResult
    static func backup(sourceURL: URL) throws -> URL {
        let backupDir = sourceURL.deletingLastPathComponent().appending(path: "backups", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            throw XLSXWorkbookKitError.backupFailed("Could not create backup directory: \(error)")
        }
        let timestamp = DateFormatter.spinlabXLSXBackup.string(from: .now)
        let backupURL = backupDir.appending(path: "registry_source_backup_\(timestamp)_\(UUID().uuidString.prefix(8)).xlsx")
        do {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
        } catch {
            throw XLSXWorkbookKitError.backupFailed("Could not copy \(sourceURL.path) to \(backupURL.path): \(error)")
        }
        return backupURL
    }

    /// Content fingerprint of a workbook file, for TOCTOU detection between
    /// plan generation and plan apply (Phase 5A spec §3). Content hash, not
    /// path/mtime — a manual re-save that leaves size/mtime alone but edits
    /// a cell must still be caught, and mtime is unreliable across some
    /// cloud-sync backends.
    static func contentFingerprint(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension DateFormatter {
    static let spinlabXLSXBackup: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

