import CoreXLSX
import Foundation

struct SampleRegistryLookupResult {
    let sampleID: String
    let prefix: String
    let sheetName: String
    let metadata: [String: String]
}

struct SampleRegistrySnapshotEntry: Codable, Hashable, Sendable {
    let sampleID: String
    let prefix: String
    let sheetName: String
    let metadata: [String: String]
}

struct SampleRegistrySnapshot: Codable, Hashable, Sendable {
    let sourceFilePath: String?
    let prefixToSheet: [String: String]
    let entriesBySampleID: [String: SampleRegistrySnapshotEntry]

    static func empty(sourceFilePath: String? = nil) -> SampleRegistrySnapshot {
        SampleRegistrySnapshot(sourceFilePath: sourceFilePath, prefixToSheet: [:], entriesBySampleID: [:])
    }
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

struct SnapshotSampleRegistryIndex: SampleRegistryIndexing {
    let snapshot: SampleRegistrySnapshot

    var sourceFilePath: String? { snapshot.sourceFilePath }
    var prefixToSheet: [String: String] { snapshot.prefixToSheet }
    var isLoaded: Bool { !snapshot.entriesBySampleID.isEmpty }

    func sampleID(from filename: String) -> String? {
        SampleIDParser.extractSampleID(fromFilename: filename)
    }

    func lookup(sampleID: String) -> SampleRegistryLookupResult? {
        let normalized = sampleID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, let entry = snapshot.entriesBySampleID[normalized] else {
            return nil
        }
        return SampleRegistryLookupResult(
            sampleID: sampleID,
            prefix: entry.prefix,
            sheetName: entry.sheetName,
            metadata: entry.metadata
        )
    }

    func lookup(from filename: String) -> SampleRegistryLookupResult? {
        guard let extracted = sampleID(from: filename) else {
            return nil
        }
        return lookup(sampleID: extracted)
    }
}

final class XLSXPrefixSampleRegistryIndex: SampleRegistryIndexing {
    private struct IndexedRegistryRow {
        let sheetName: String
        let sheetOrder: Int
        let rowNumber: Int
        let metadata: [String: String]
    }

    private let lookupRules: any RegistryLookupRuleProviding
    private let entriesBySampleID: [String: SampleRegistrySnapshotEntry]

    let sourceFilePath: String?
    let prefixToSheet: [String: String]
    let isLoaded: Bool = true

    var snapshot: SampleRegistrySnapshot {
        SampleRegistrySnapshot(
            sourceFilePath: sourceFilePath,
            prefixToSheet: prefixToSheet,
            entriesBySampleID: entriesBySampleID
        )
    }

    init(
        xlsxURL: URL,
        previewRowCount: Int = 10,
        lookupRules: any RegistryLookupRuleProviding = RegistryLookupRuleBook()
    ) throws {
        guard let file = XLSXFile(filepath: xlsxURL.path) else {
            throw NSError(domain: "SampleRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to open XLSX file at \(xlsxURL.path)."])
        }

        self.lookupRules = lookupRules
        sourceFilePath = xlsxURL.path

        guard let workbook = try file.parseWorkbooks().first else {
            throw NSError(domain: "SampleRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "No workbook found in XLSX file."])
        }
        let sharedStrings = try? file.parseSharedStrings()

        let worksheetPathsAndNames = try file.parseWorksheetPathsAndNames(workbook: workbook)
        let orderedSheets: [(sheetName: String, path: String)] = worksheetPathsAndNames.compactMap { name, path in
            guard let name else {
                return nil
            }
            return (sheetName: name, path: path)
        }

        let built = try Self.buildIndex(
            file: file,
            sharedStrings: sharedStrings,
            orderedSheets: orderedSheets,
            previewRowCount: max(1, previewRowCount),
            lookupRules: lookupRules
        )
        entriesBySampleID = built.entriesBySampleID
        prefixToSheet = built.prefixToSheet
    }

    static func fromEnvironment(previewRowCount: Int = 10) -> SampleRegistryIndexing {
        guard let xlsxURL = registryFileURLFromEnvironment() else {
            return SnapshotSampleRegistryIndex(snapshot: .empty())
        }

        guard let index = try? XLSXPrefixSampleRegistryIndex(xlsxURL: xlsxURL, previewRowCount: previewRowCount) else {
            return SnapshotSampleRegistryIndex(snapshot: .empty(sourceFilePath: xlsxURL.path))
        }
        return SnapshotSampleRegistryIndex(snapshot: index.snapshot)
    }

    static func fromFileURL(_ xlsxURL: URL, previewRowCount: Int = 10) -> SampleRegistryIndexing {
        guard let index = try? XLSXPrefixSampleRegistryIndex(xlsxURL: xlsxURL, previewRowCount: previewRowCount) else {
            return SnapshotSampleRegistryIndex(snapshot: .empty(sourceFilePath: xlsxURL.path))
        }
        return SnapshotSampleRegistryIndex(snapshot: index.snapshot)
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

    private static func buildIndex(
        file: XLSXFile,
        sharedStrings: SharedStrings?,
        orderedSheets: [(sheetName: String, path: String)],
        previewRowCount: Int,
        lookupRules: any RegistryLookupRuleProviding
    ) throws -> (entriesBySampleID: [String: SampleRegistrySnapshotEntry], prefixToSheet: [String: String]) {
        var rowsBySampleID: [String: [IndexedRegistryRow]] = [:]
        var prefixToSheet: [String: String] = [:]

        for (sheetOrder, sheet) in orderedSheets.enumerated() {
            guard let worksheet = try? file.parseWorksheet(at: sheet.path),
                  let rows = worksheet.data?.rows,
                  rows.count > 1 else {
                continue
            }

            let headerByColumn = headerValueByColumnIndex(row: rows[0], sharedStrings: sharedStrings)
            guard lookupRules.shouldIndexSheet(named: sheet.sheetName, headerByColumn: headerByColumn),
                  let sampleColumn = lookupRules.sampleColumnIndex(headerByColumn: headerByColumn) else {
                continue
            }

            var previewCount = 0
            for (rowOffset, row) in rows.dropFirst().enumerated() {
                guard let rawSampleID = rowValue(row: row, atColumn: sampleColumn, sharedStrings: sharedStrings) else {
                    continue
                }

                let candidates = lookupRules.sampleIDCandidates(from: rawSampleID)
                guard !candidates.isEmpty else {
                    continue
                }

                let metadata = rowMetadata(row: row, headerByColumn: headerByColumn, sharedStrings: sharedStrings)
                let indexed = IndexedRegistryRow(
                    sheetName: sheet.sheetName,
                    sheetOrder: sheetOrder,
                    rowNumber: rowOffset + 2,
                    metadata: metadata
                )

                for candidate in candidates {
                    rowsBySampleID[candidate, default: []].append(indexed)
                    if previewCount < previewRowCount,
                       let prefix = SampleIDParser.extractPrefix(fromSampleID: candidate),
                       prefixToSheet[prefix] == nil {
                        prefixToSheet[prefix] = sheet.sheetName
                    }
                }

                previewCount += 1
            }
        }

        for sampleID in rowsBySampleID.keys {
            rowsBySampleID[sampleID]?.sort {
                if $0.sheetOrder == $1.sheetOrder {
                    return $0.rowNumber < $1.rowNumber
                }
                return $0.sheetOrder < $1.sheetOrder
            }
        }

        var entriesBySampleID: [String: SampleRegistrySnapshotEntry] = [:]
        entriesBySampleID.reserveCapacity(rowsBySampleID.count)

        for (sampleID, rows) in rowsBySampleID {
            guard let first = rows.first else {
                continue
            }
            let prefix = SampleIDParser.extractPrefix(fromSampleID: sampleID) ?? ""
            entriesBySampleID[sampleID] = SampleRegistrySnapshotEntry(
                sampleID: sampleID,
                prefix: prefix,
                sheetName: first.sheetName,
                metadata: first.metadata
            )
        }

        return (entriesBySampleID, prefixToSheet)
    }

    private func lookupInternal(sampleID: String) -> SampleRegistryLookupResult? {
        let normalizedSampleID = lookupRules.normalizedLookupSampleID(sampleID)
        guard !normalizedSampleID.isEmpty,
              let entry = entriesBySampleID[normalizedSampleID] else {
            return nil
        }

        return SampleRegistryLookupResult(
            sampleID: sampleID,
            prefix: entry.prefix,
            sheetName: entry.sheetName,
            metadata: entry.metadata
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
