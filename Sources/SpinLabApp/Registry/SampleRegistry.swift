import CoreXLSX
import Foundation

struct SampleRegistryLookupResult {
    let sampleID: String
    let prefix: String
    let sheetName: String
    let metadata: [String: String]
}

struct RegistryPrefixEntry: Identifiable, Hashable {
    let prefix: String
    let sheetName: String

    var id: String { prefix }
}

protocol SampleRegistryIndexing {
    var sourceFilePath: String? { get }
    var prefixToSheet: [String: String] { get }
    var isLoaded: Bool { get }
    func sampleID(from filename: String) -> String?
    func lookup(sampleID: String) -> SampleRegistryLookupResult?
    func lookup(from filename: String) -> SampleRegistryLookupResult?
}

struct NoopSampleRegistryIndex: SampleRegistryIndexing {
    let sourceFilePath: String? = nil
    let prefixToSheet: [String: String] = [:]
    let isLoaded = false

    func sampleID(from filename: String) -> String? {
        SampleIDParser.extractSampleID(fromFilename: filename)
    }

    func lookup(sampleID: String) -> SampleRegistryLookupResult? {
        nil
    }

    func lookup(from filename: String) -> SampleRegistryLookupResult? {
        nil
    }
}

final class XLSXPrefixSampleRegistryIndex: SampleRegistryIndexing {
    private let file: XLSXFile
    private let worksheetPathsByName: [String: String]
    private let sharedStrings: SharedStrings?
    private let previewRowCount: Int

    let sourceFilePath: String?
    let prefixToSheet: [String: String]
    let isLoaded: Bool = true

    init(xlsxURL: URL, previewRowCount: Int = 10) throws {
        guard let file = XLSXFile(filepath: xlsxURL.path) else {
            throw NSError(domain: "SampleRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to open XLSX file at \(xlsxURL.path)."])
        }

        self.file = file
        self.previewRowCount = max(1, previewRowCount)
        sourceFilePath = xlsxURL.path

        guard let workbook = try file.parseWorkbooks().first else {
            throw NSError(domain: "SampleRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "No workbook found in XLSX file."])
        }
        sharedStrings = try? file.parseSharedStrings()

        let worksheetPathsAndNames = try file.parseWorksheetPathsAndNames(workbook: workbook)
        var byName: [String: String] = [:]
        for (name, path) in worksheetPathsAndNames {
            guard let name else {
                continue
            }
            byName[name] = path
        }
        worksheetPathsByName = byName
        prefixToSheet = try Self.buildPrefixMap(
            file: file,
            sharedStrings: sharedStrings,
            worksheetPathsByName: worksheetPathsByName,
            previewRowCount: self.previewRowCount
        )
    }

    static func fromEnvironment(previewRowCount: Int = 10) -> SampleRegistryIndexing {
        guard let xlsxURL = registryFileURLFromEnvironment() else {
            return NoopSampleRegistryIndex()
        }

        return (try? XLSXPrefixSampleRegistryIndex(xlsxURL: xlsxURL, previewRowCount: previewRowCount)) ?? NoopSampleRegistryIndex()
    }

    static func fromFileURL(_ xlsxURL: URL, previewRowCount: Int = 10) -> SampleRegistryIndexing {
        (try? XLSXPrefixSampleRegistryIndex(xlsxURL: xlsxURL, previewRowCount: previewRowCount)) ?? NoopSampleRegistryIndex()
    }

    func sampleID(from filename: String) -> String? {
        SampleIDParser.extractSampleID(fromFilename: filename)
    }

    func lookup(sampleID: String) -> SampleRegistryLookupResult? {
        lookupInternal(sampleID: sampleID)
    }

    func lookup(from filename: String) -> SampleRegistryLookupResult? {
        guard let sampleID = sampleID(from: filename) else {
            return nil
        }
        return lookupInternal(sampleID: sampleID)
    }

    private static func registryFileURLFromEnvironment() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let configuredPath = environment["SPINLAB_SAMPLE_REGISTRY_XLSX"], !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath)
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "sample_registry.xlsx")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        return nil
    }

    private static func buildPrefixMap(
        file: XLSXFile,
        sharedStrings: SharedStrings?,
        worksheetPathsByName: [String: String],
        previewRowCount: Int
    ) throws -> [String: String] {
        var map: [String: String] = [:]

        for (sheetName, worksheetPath) in worksheetPathsByName {
            guard let worksheet = try? file.parseWorksheet(at: worksheetPath),
                  let rows = worksheet.data?.rows,
                  rows.count > 1 else {
                continue
            }

            let headerByColumn = headerValueByColumnIndex(row: rows[0], sharedStrings: sharedStrings)
            let sampleColumn = sampleColumnIndex(headerByColumn: headerByColumn) ?? 1

            var collectedPreviewIDs = 0

            for row in rows.dropFirst() {
                guard
                    let sampleID = rowValue(row: row, atColumn: sampleColumn, sharedStrings: sharedStrings),
                    let prefix = SampleIDParser.extractPrefix(fromSampleID: sampleID)
                else {
                    continue
                }
                if map[prefix] == nil {
                    map[prefix] = sheetName
                }
                collectedPreviewIDs += 1
                if collectedPreviewIDs >= previewRowCount {
                    break
                }
            }
        }

        return map
    }

    private static func sampleColumnIndex(headerByColumn: [Int: String]) -> Int? {
        for (column, header) in headerByColumn {
            let normalized = header.lowercased().replacingOccurrences(of: "_", with: "")
            if normalized == "sampleid" || normalized == "sample" || header == "编号" {
                return column
            }
        }
        return nil
    }

    private func lookupInternal(sampleID: String) -> SampleRegistryLookupResult? {
        guard
            let prefix = SampleIDParser.extractPrefix(fromSampleID: sampleID),
            let sheetName = prefixToSheet[prefix],
            let worksheetPath = worksheetPathsByName[sheetName],
            let worksheet = try? file.parseWorksheet(at: worksheetPath),
            let rows = worksheet.data?.rows,
            !rows.isEmpty
        else {
            return nil
        }

        let headerRow = rows[0]
        let headerByColumn = Self.headerValueByColumnIndex(row: headerRow, sharedStrings: sharedStrings)
        let sampleColumnIndex = Self.sampleColumnIndex(headerByColumn: headerByColumn) ?? 1

        for row in rows.dropFirst() {
            guard let rowSampleID = Self.rowValue(row: row, atColumn: sampleColumnIndex, sharedStrings: sharedStrings) else {
                continue
            }

            let candidates = rowSampleID
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

            if !candidates.contains(sampleID.uppercased()) {
                continue
            }

            let metadata = Self.rowMetadata(row: row, headerByColumn: headerByColumn, sharedStrings: sharedStrings)
            return SampleRegistryLookupResult(
                sampleID: sampleID,
                prefix: prefix,
                sheetName: sheetName,
                metadata: metadata
            )
        }

        return SampleRegistryLookupResult(
            sampleID: sampleID,
            prefix: prefix,
            sheetName: sheetName,
            metadata: [:]
        )
    }

    private static func headerValueByColumnIndex(row: Row, sharedStrings: SharedStrings?) -> [Int: String] {
        var headerByColumn: [Int: String] = [:]
        for cell in row.cells {
            guard
                let column = columnIndex(for: cell),
                let value = cellString(cell: cell, sharedStrings: sharedStrings)
            else {
                continue
            }
            headerByColumn[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headerByColumn
    }

    private static func rowMetadata(row: Row, headerByColumn: [Int: String], sharedStrings: SharedStrings?) -> [String: String] {
        var metadata: [String: String] = [:]
        for cell in row.cells {
            guard
                let column = columnIndex(for: cell),
                let value = cellString(cell: cell, sharedStrings: sharedStrings),
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            let key = headerByColumn[column] ?? "Column\(column)"
            metadata[key] = value
        }
        return metadata
    }

    private static func rowValue(row: Row, atColumn column: Int, sharedStrings: SharedStrings?) -> String? {
        for cell in row.cells {
            guard columnIndex(for: cell) == column else {
                continue
            }
            guard let value = cellString(cell: cell, sharedStrings: sharedStrings) else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func cellString(cell: Cell, sharedStrings: SharedStrings?) -> String? {
        if let sharedStrings {
            return cell.stringValue(sharedStrings)
        }
        return cell.value
    }

    private static func columnIndex(for cell: Cell) -> Int? {
        let reference = cell.reference
        return columnIndex(from: reference.column.value)
    }

    private static func columnIndex(from columnLabel: String) -> Int? {
        var value = 0
        for character in columnLabel.uppercased().unicodeScalars {
            guard character.value >= 65, character.value <= 90 else {
                continue
            }
            value = (value * 26) + Int(character.value - 64)
        }
        return value == 0 ? nil : value
    }
}

enum SampleIDParser {
    static func extractSampleID(fromFilename filename: String) -> String? {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let tokens = tokenize(stem, separators: RuleLoader.shared.loadCached().ruleSet.tokenization.separators)
        return extractSampleIDs(fromTokens: tokens).first
    }

    static func extractSampleIDs(fromTokens tokens: [String]) -> [String] {
        RuleLoader.shared.loadCached().ruleSet.sampleIDs(from: tokens)
    }

    static func extractPrefix(fromSampleID sampleID: String) -> String? {
        let letters = sampleID.prefix(while: \.isLetter)
        guard letters.count >= 2 else {
            return nil
        }
        return letters.uppercased()
    }

    private static func tokenize(_ value: String, separators: String) -> [String] {
        value
            .split(whereSeparator: { separators.contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
