import CoreXLSX
import Foundation

final class LibraryRegistryParser {
    struct ParsedResult {
        var index: LibraryIndex
        var warnings: [LibraryWarning]
    }

    private let substrateParser = LibrarySubstrateParser()

    func parse(xlsxURL: URL, settings: LibrarySettings) -> ParsedResult {
        var warnings: [LibraryWarning] = []
        guard let file = XLSXFile(filepath: xlsxURL.path) else {
            let warning = LibraryWarning(message: "Unable to open XLSX at \(xlsxURL.path)", affectedSampleKey: nil, severity: .error)
            return ParsedResult(
                index: LibraryIndex(
                    createdAt: .now,
                    updatedAt: .now,
                    registryInternalPath: xlsxURL.path,
                    registrySourcePath: settings.registrySourcePath,
                    metadataColumnOrder: [],
                    batches: [],
                    samples: []
                ),
                warnings: [warning]
            )
        }

        guard let workbook = try? file.parseWorkbooks().first else {
            let warning = LibraryWarning(message: "No workbook found in XLSX.", affectedSampleKey: nil, severity: .error)
            return ParsedResult(
                index: LibraryIndex(
                    createdAt: .now,
                    updatedAt: .now,
                    registryInternalPath: xlsxURL.path,
                    registrySourcePath: settings.registrySourcePath,
                    metadataColumnOrder: [],
                    batches: [],
                    samples: []
                ),
                warnings: [warning]
            )
        }

        let sharedStrings = try? file.parseSharedStrings()
        let worksheetPathsAndNames = (try? file.parseWorksheetPathsAndNames(workbook: workbook)) ?? []
        let now = Date()
        var batchesByID: [String: LibraryBatch] = [:]
        var samplesByKey: [String: LibrarySample] = [:]
        var globalMetadataColumnOrder: [String] = []
        var seenMetadataColumns: Set<String> = []

        for (sheetNameMaybe, worksheetPath) in worksheetPathsAndNames {
            guard let sheetName = sheetNameMaybe else {
                continue
            }
            if sheetName == "实验大纲" {
                continue
            }
            guard let worksheet = try? file.parseWorksheet(at: worksheetPath),
                  let rows = worksheet.data?.rows,
                  !rows.isEmpty
            else {
                continue
            }

            let headerByColumn = Self.headerValueByColumnIndex(row: rows[0], sharedStrings: sharedStrings)
            let sheetMetadataColumnOrder = Self.orderedHeaderValues(headerByColumn: headerByColumn)
            for key in sheetMetadataColumnOrder where !seenMetadataColumns.contains(key) {
                seenMetadataColumns.insert(key)
                globalMetadataColumnOrder.append(key)
            }
            guard let batchColumn = Self.columnIndex(for: headerByColumn, names: ["编号", "Batch", "BatchID", "Batch Id"]) else {
                continue
            }
            let substrateColumn = Self.columnIndex(for: headerByColumn, names: ["substrate", "Substrate", "衬底"]) 

            for (rowIndex, row) in rows.dropFirst().enumerated() {
                guard let rawBatchValue = Self.rowValue(row: row, atColumn: batchColumn, sharedStrings: sharedStrings) else {
                    continue
                }
                let batchId = rawBatchValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !shouldInclude(batchId: batchId, settings: settings) {
                    continue
                }

                let metadata = Self.rowMetadata(row: row, headerByColumn: headerByColumn, sharedStrings: sharedStrings)
                let orderedMetadata = Self.orderedMetadata(
                    row: row,
                    orderedKeys: sheetMetadataColumnOrder,
                    headerByColumn: headerByColumn,
                    sharedStrings: sharedStrings
                )
                let substrateRaw = substrateColumn.flatMap { Self.rowValue(row: row, atColumn: $0, sharedStrings: sharedStrings) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let substrates = substrateParser.parse(substrateRaw)
                if substrates.isEmpty {
                    let warning = LibraryWarning(message: "No substrate parsed for batch \(batchId) on sheet \(sheetName), row \(rowIndex + 2)", affectedSampleKey: nil, severity: .warning)
                    warnings.append(warning)
                }

                let batch = batchesByID[batchId] ?? LibraryBatch(
                    id: batchId,
                    displayName: batchId,
                    sheetName: sheetName,
                    metadata: metadata,
                    numericTags: Self.numericTags(from: metadata).tags,
                    numericDisplay: Self.numericTags(from: metadata).display,
                    sampleKeys: [],
                    updatedAt: now
                )

                var updatedBatch = batch
                if updatedBatch.metadata != metadata {
                    updatedBatch.metadata = mergeMetadata(existing: updatedBatch.metadata, incoming: metadata)
                    let numeric = Self.numericTags(from: updatedBatch.metadata)
                    updatedBatch.numericTags = numeric.tags
                    updatedBatch.numericDisplay = numeric.display
                    updatedBatch.updatedAt = now
                }
                batchesByID[batchId] = updatedBatch

                for substrate in substrates {
                    let sampleKey = substrateParser.sampleKey(batchId: batchId, substrate: substrate)
                    if samplesByKey[sampleKey] != nil {
                        let warning = LibraryWarning(message: "Duplicate sampleKey \(sampleKey) in registry.", affectedSampleKey: sampleKey, severity: .error)
                        warnings.append(warning)
                        continue
                    }
                    let displayName = "\(batchId) - \(substrate.display)"
                    let numeric = Self.numericTags(from: metadata)
                    let sample = LibrarySample(
                        id: sampleKey,
                        displayName: displayName,
                        batchId: batchId,
                        substrateRaw: substrateRaw,
                        substrateDisplay: substrate.display,
                        substrateTokens: substrate.tokens,
                        substrateTags: substrate.searchTags,
                        metadata: metadata,
                        orderedMetadata: orderedMetadata,
                        numericTags: numeric.tags,
                        numericDisplay: numeric.display,
                        sourceSheetName: sheetName,
                        sourceRowNumber: rowIndex + 2,
                        updatedAt: now
                    )
                    samplesByKey[sampleKey] = sample

                    if !updatedBatch.sampleKeys.contains(sampleKey) {
                        updatedBatch.sampleKeys.append(sampleKey)
                        batchesByID[batchId] = updatedBatch
                    }
                }
            }
        }

        let index = LibraryIndex(
            createdAt: now,
            updatedAt: now,
            registryInternalPath: xlsxURL.path,
            registrySourcePath: settings.registrySourcePath,
            metadataColumnOrder: globalMetadataColumnOrder,
            batches: Array(batchesByID.values).sorted { $0.id < $1.id },
            samples: Array(samplesByKey.values).sorted { $0.displayName < $1.displayName }
        )

        return ParsedResult(index: index, warnings: warnings)
    }

    private func shouldInclude(batchId: String, settings: LibrarySettings) -> Bool {
        let prefixes = settings.allowedBatchPrefixes.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !prefixes.isEmpty else {
            return true
        }
        let upper = batchId.uppercased()
        return prefixes.contains(where: { upper.hasPrefix($0) })
    }

    private func mergeMetadata(existing: [String: String], incoming: [String: String]) -> [String: String] {
        var merged = existing
        for (key, value) in incoming {
            merged[key] = value
        }
        return merged
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
                let value = cellString(cell: cell, sharedStrings: sharedStrings)
            else {
                continue
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = headerByColumn[column] ?? "Column\(column)"
            metadata[key] = trimmed
        }
        return metadata
    }

    private static func orderedHeaderValues(headerByColumn: [Int: String]) -> [String] {
        headerByColumn
            .keys
            .sorted()
            .compactMap { column in
                let value = headerByColumn[column]?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }
    }

    private static func orderedMetadata(
        row: Row,
        orderedKeys: [String],
        headerByColumn: [Int: String],
        sharedStrings: SharedStrings?
    ) -> [LibraryMetadataItem] {
        let metadata = rowMetadata(row: row, headerByColumn: headerByColumn, sharedStrings: sharedStrings)
        return orderedKeys.map { key in
            LibraryMetadataItem(key: key, value: metadata[key] ?? "")
        }
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

    private static func columnIndex(for headerByColumn: [Int: String], names: [String]) -> Int? {
        for (column, header) in headerByColumn {
            if names.contains(header) {
                return column
            }
        }
        return nil
    }

    private static func numericTags(from metadata: [String: String]) -> (tags: [String: Double], display: [String: String]) {
        var tags: [String: Double] = [:]
        var display: [String: String] = [:]
        for (key, value) in metadata {
            guard let normalizedKey = normalizeNumericKey(key),
                  let number = numericValue(for: normalizedKey, value: value)
            else {
                continue
            }
            tags[normalizedKey] = number
            display[normalizedKey] = formatDisplayValue(for: normalizedKey, value: value, number: number)
        }
        return (tags, display)
    }

    static func normalizeNumericKey(_ key: String) -> String? {
        let lowered = key.lowercased()
        if lowered.contains("预打") || lowered.contains("生长次数") {
            return "厚度"
        }
        if lowered.contains("温度") || lowered.contains("temperature") {
            return "温度"
        }
        if lowered.contains("氧压") || lowered.contains("pressure") || lowered.contains("压") {
            return "氧压"
        }
        if lowered.contains("能量") || lowered.contains("energy") {
            return "能量"
        }
        if lowered.contains("电压") || lowered.contains("kv") {
            return "电压"
        }
        if lowered.contains("磁场") || lowered.contains("field") {
            return "磁场"
        }
        if lowered.contains("电阻") || lowered.contains("current") {
            return "电阻"
        }
        return nil
    }

    private static func numericValue(for key: String, value: String) -> Double? {
        switch key {
        case "能量":
            return energyNumber(in: value) ?? firstNumber(in: value)
        case "厚度":
            return growthCount(in: value)
        default:
            return firstNumber(in: value)
        }
    }

    private static func firstNumber(in value: String) -> Double? {
        let pattern = "[-+]?\\d+(?:\\.\\d+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else {
            return nil
        }
        guard let numberRange = Range(match.range, in: value) else {
            return nil
        }
        return Double(value[numberRange])
    }

    private static func energyNumber(in value: String) -> Double? {
        let pattern = "([-+]?\\d+(?:\\.\\d+)?)\\s*mj"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else {
            return nil
        }
        guard let numberRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Double(value[numberRange])
    }

    private static func growthCount(in value: String) -> Double? {
        if let slashRange = value.range(of: "/") {
            let afterSlash = value[slashRange.upperBound...]
            return firstNumber(in: String(afterSlash))
        }
        return nil
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func formatDisplayValue(for key: String, value: String, number: Double) -> String {
        let lower = value.lowercased()
        if key == "能量" {
            return "\(formatNumber(number)) mJ"
        }
        if key == "厚度" {
            return "\(formatNumber(number)) ps"
        }
        if lower.contains("kv") {
            return "\(formatNumber(number)) kV"
        }
        if lower.contains("mt") {
            return "\(formatNumber(number)) mT"
        }
        if lower.contains("mj") {
            return "\(formatNumber(number)) mJ"
        }
        if key == "温度" {
            return "\(formatNumber(number)) °C"
        }
        if key == "氧压" {
            return "\(formatNumber(number)) mT"
        }
        if key == "电压" {
            return "\(formatNumber(number)) kV"
        }
        return formatNumber(number)
    }
}

struct LibrarySubstrate {
    var display: String
    var tokens: [String]
    var searchTags: [String]
    var material: String?
    var orientation: String?
}

final class LibrarySubstrateParser {
    private let materialTokens = [
        "STO",
        "NGO",
        "MAO",
        "MGO",
        "AL2O3",
        "SI",
        "POLY-SIO2 ON SI",
        "POLY-SIO2"
    ]

    func parse(_ raw: String) -> [LibrarySubstrate] {
        let cleaned = raw
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
        let segments = cleaned
            .split(whereSeparator: { ",;".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !segments.isEmpty else {
            return []
        }

        return segments.map { parseSegment($0) }
    }

    func sampleKey(batchId: String, substrate: LibrarySubstrate) -> String {
        SampleSemanticDescriptor
            .fromLibrarySubstrate(
                batchId: batchId,
                substrateTokens: substrate.tokens,
                material: substrate.material,
                orientation: substrate.orientation
            )
            .canonicalKey ?? "\(batchId)||UNKNOWN|UNKNOWN"
    }

    private func parseSegment(_ segment: String) -> LibrarySubstrate {
        let upper = segment.uppercased()
        let material = materialTokens.first(where: { upper.contains($0) })
        let orientation = parseOrientation(upper)
        let processing = parseProcessingTokens(upper)

        let displayMaterial = materialDisplay(material, original: segment)
        let displayOrientation = orientation.map { "(\($0))" } ?? ""
        let displayProcessing = displayProcessingPrefix(processing)
        let display = (displayProcessing + displayMaterial + displayOrientation).trimmingCharacters(in: .whitespacesAndNewlines)

        let tokens = processing + [material ?? "UNKNOWN", orientation ?? "UNKNOWN"]
        let baseTag = (material ?? "UNKNOWN") + (orientation.map { "(\($0))" } ?? "")
        var searchTags = [material ?? "UNKNOWN", baseTag]
        if !processing.isEmpty {
            let processingPrefix = processing.sorted().joined(separator: " ")
            searchTags.append("\(processingPrefix) \(baseTag)")
        }

        return LibrarySubstrate(
            display: display.isEmpty ? segment : display,
            tokens: tokens,
            searchTags: searchTags,
            material: material,
            orientation: orientation
        )
    }

    private func parseProcessingTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        if value.contains("HF") {
            tokens.append("HF")
        }
        if value.contains("BAKE") || value.contains("BAKED") {
            tokens.append("baked")
        }
        if value.contains("ORIGINAL") || value.contains("ORIGIN") || value.contains(" O ") || value.hasPrefix("O ") {
            tokens.append("o")
        }
        return Array(Set(tokens))
    }

    private func parseOrientation(_ value: String) -> String? {
        if value.contains("0001") {
            return "0001"
        }
        if value.contains("111") {
            return "111"
        }
        if value.contains("110") {
            return "110"
        }
        if value.contains("100") || value.contains("001") {
            return "001"
        }
        return nil
    }

    private func materialDisplay(_ material: String?, original: String) -> String {
        guard let material else {
            return original.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if material == "POLY-SIO2 ON SI" || material == "POLY-SIO2" {
            return "poly-SiO2 on Si"
        }
        if material == "MGO" {
            return "MgO"
        }
        if material == "AL2O3" {
            return "Al2O3"
        }
        if material == "SI" {
            return "Si"
        }
        return material
    }

    private func displayProcessingPrefix(_ processing: [String]) -> String {
        var parts: [String] = []
        if processing.contains("o") {
            parts.append("o")
        }
        if processing.contains("HF") {
            parts.append("HF")
        }
        if processing.contains("baked") {
            parts.append("baked")
        }
        if parts.isEmpty {
            return ""
        }
        return parts.joined(separator: " ") + " "
    }
}
