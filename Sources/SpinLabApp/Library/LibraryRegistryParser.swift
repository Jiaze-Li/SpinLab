import CoreXLSX
import Foundation

final class LibraryRegistryParser {
    struct ParsedResult {
        var index: LibraryIndex
        var warnings: [LibraryWarning]
    }

    private let substrateParser: LibrarySubstrateParser
    private let excludedSheetNames: Set<String>
    private let batchHeaderAliases: Set<String>
    private let substrateHeaderAliases: Set<String>
    private let numericKeyAliases: [String: [String]]
    private static let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        let registryRules = ruleProvider.registryRules()
        guard let config = ruleProvider.substrateConfig() else {
            AppLogger.shared.error(.import, "LibraryRegistryParser: substrateConfig unavailable — v2 schema required")
            substrateParser = LibrarySubstrateParser(
                materialTokens: [],
                processingKeywords: [:],
                orientationTokens: [],
                orientationAliases: [:],
                materialDisplayNames: [:]
            )
            excludedSheetNames = Set(registryRules.excludedSheetNames)
            batchHeaderAliases = Set(registryRules.batchHeaderAliases)
            substrateHeaderAliases = Set(registryRules.substrateHeaderAliases)
            numericKeyAliases = registryRules.numericKeyAliases
            return
        }
        substrateParser = LibrarySubstrateParser(
            materialTokens: config.materials.flatMap { m in
                ([m.id] + m.tokens).map { $0.uppercased() }
            },
            processingKeywords: Dictionary(uniqueKeysWithValues: config.treatments.map { t in
                (t.id, t.keywords.map { $0.uppercased() })
            }),
            orientationTokens: config.orientations.rows.flatMap { row in
                (row.tokens + row.aliases).map { $0.uppercased() }
            },
            orientationAliases: config.orientations.rows.reduce(into: [:]) { partial, row in
                for alias in row.aliases {
                    partial[alias.uppercased()] = row.id.uppercased()
                }
            },
            materialDisplayNames: config.materials.reduce(into: [:]) { partial, m in
                partial[m.id.uppercased()] = m.displayName
                for token in m.tokens {
                    partial[token.uppercased()] = m.displayName
                }
            }
        )
        excludedSheetNames = Set(registryRules.excludedSheetNames)
        batchHeaderAliases = Set(registryRules.batchHeaderAliases)
        substrateHeaderAliases = Set(registryRules.substrateHeaderAliases)
        numericKeyAliases = registryRules.numericKeyAliases
    }

    convenience init(ruleLoadResult: RuleLoader.LoadResult) {
        let provider = InlineRuleProvider(loadResult: ruleLoadResult)
        self.init(ruleProvider: provider)
    }

    func parse(xlsxURL: URL, settings: LibrarySettings) throws -> ParsedResult {
        var warnings: [LibraryWarning] = []
        guard let file = XLSXFile(filepath: xlsxURL.path) else {
            throw AppError.io("Unable to open XLSX at \(xlsxURL.path)")
        }

        let workbook: Workbook
        do {
            guard let parsedWorkbook = try file.parseWorkbooks().first else {
                throw AppError.io("No workbook found in XLSX.")
            }
            workbook = parsedWorkbook
        } catch {
            throw AppError.from(error, fallback: "Failed to parse workbook from XLSX.")
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
            if RegistrySheetFilter.shouldSkipSheet(named: sheetName, excludedSheetNames: excludedSheetNames) {
                continue
            }
            guard let worksheet = try? file.parseWorksheet(at: worksheetPath),
                  let rows = worksheet.data?.rows,
                  !rows.isEmpty
            else {
                continue
            }

            let headerByColumn = XLSXSheetValueReader.headerValueByColumnIndex(row: rows[0], sharedStrings: sharedStrings)
            let sheetMetadataColumnOrder = Self.orderedHeaderValues(headerByColumn: headerByColumn)
            for key in sheetMetadataColumnOrder where !seenMetadataColumns.contains(key) {
                seenMetadataColumns.insert(key)
                globalMetadataColumnOrder.append(key)
            }
            guard let batchColumn = Self.columnIndex(for: headerByColumn, aliases: batchHeaderAliases) else {
                continue
            }
            let substrateColumn = Self.columnIndex(for: headerByColumn, aliases: substrateHeaderAliases)

            for (rowIndex, row) in rows.dropFirst().enumerated() {
                guard let rawBatchValue = XLSXSheetValueReader.rowValue(row: row, atColumn: batchColumn, sharedStrings: sharedStrings) else {
                    continue
                }
                let batchId = rawBatchValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !shouldInclude(batchId: batchId, settings: settings) {
                    continue
                }

                let metadata = XLSXSheetValueReader.rowMetadata(row: row, headerByColumn: headerByColumn, sharedStrings: sharedStrings)
                let orderedMetadata = Self.orderedMetadata(
                    row: row,
                    orderedKeys: sheetMetadataColumnOrder,
                    headerByColumn: headerByColumn,
                    sharedStrings: sharedStrings
                )
                let substrateRaw = substrateColumn.flatMap {
                    XLSXSheetValueReader.rowValue(row: row, atColumn: $0, sharedStrings: sharedStrings)
                }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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
                    numericTags: Self.numericTags(from: metadata, aliases: numericKeyAliases).tags,
                    numericDisplay: Self.numericTags(from: metadata, aliases: numericKeyAliases).display,
                    sampleKeys: [],
                    updatedAt: now
                )

                var updatedBatch = batch
                if updatedBatch.metadata != metadata {
                    updatedBatch.metadata = mergeMetadata(existing: updatedBatch.metadata, incoming: metadata)
                    let numeric = Self.numericTags(from: updatedBatch.metadata, aliases: numericKeyAliases)
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
                    let numeric = Self.numericTags(from: metadata, aliases: numericKeyAliases)
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
        let metadata = XLSXSheetValueReader.rowMetadata(row: row, headerByColumn: headerByColumn, sharedStrings: sharedStrings)
        return orderedKeys.map { key in
            LibraryMetadataItem(key: key, value: metadata[key] ?? "")
        }
    }

    private static func columnIndex(for headerByColumn: [Int: String], aliases: Set<String>) -> Int? {
        for (column, header) in headerByColumn {
            if aliases.contains(header) {
                return column
            }
        }
        return nil
    }

    private static func numericTags(from metadata: [String: String], aliases: [String: [String]]) -> (tags: [String: Double], display: [String: String]) {
        var tags: [String: Double] = [:]
        var display: [String: String] = [:]
        for (key, value) in metadata {
            guard let normalizedKey = normalizeNumericKey(key, aliases: aliases),
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
        normalizeNumericKey(key, aliases: Self.ruleProvider.registryRules().numericKeyAliases)
    }

    static func normalizeNumericKey(_ key: String, aliases: [String: [String]]) -> String? {
        let lowered = key.lowercased()
        for canonicalKey in aliases.keys.sorted() {
            guard let keywords = aliases[canonicalKey] else {
                continue
            }
            if keywords.contains(where: { lowered.contains($0.lowercased()) }) {
                return canonicalKey
            }
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
        // Key-specific checks first — column header semantics always win over cell text
        if key == "能量" {
            return "\(formatNumber(number)) mJ"
        }
        if key == "厚度" {
            return "\(formatNumber(number)) ps"
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
        // Content-based fallbacks for keys without explicit unit mapping
        let lower = value.lowercased()
        if lower.contains("kv") {
            return "\(formatNumber(number)) kV"
        }
        if lower.contains("mt") {
            return "\(formatNumber(number)) mT"
        }
        if lower.contains("mj") {
            return "\(formatNumber(number)) mJ"
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
    private let materialTokens: [String]
    private let processingKeywords: [String: [String]]
    private let orientationTokens: [String]
    private let orientationAliases: [String: String]
    private let materialDisplayNames: [String: String]

    init(
        materialTokens: [String],
        processingKeywords: [String: [String]],
        orientationTokens: [String],
        orientationAliases: [String: String],
        materialDisplayNames: [String: String]
    ) {
        self.materialTokens = materialTokens
        self.processingKeywords = processingKeywords
        self.orientationTokens = orientationTokens
        self.orientationAliases = orientationAliases
        self.materialDisplayNames = materialDisplayNames
    }

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
        var parsed: [LibrarySubstrate] = []
        for segment in segments {
            if looksLikeSubstrateSegment(segment) {
                parsed.append(parseSegment(segment))
                continue
            }

            // Treat trailing non-substrate chunks as free-form notes in the same cell.
            if !parsed.isEmpty {
                break
            }
        }
        return parsed
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

    private func looksLikeSubstrateSegment(_ value: String) -> Bool {
        let upper = value.uppercased()
        if materialTokens.contains(where: { upper.contains($0) }) {
            return true
        }
        if parseOrientation(upper) != nil {
            return true
        }
        if processingKeywords.values.flatMap({ $0 }).contains(where: { keyword in
            upper.contains(keyword) || (keyword == " O " && upper.hasPrefix("O "))
        }) {
            return true
        }
        return false
    }

    private func parseProcessingTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        let separatedTokens = value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for canonical in processingKeywords.keys.sorted() {
            guard let keywords = processingKeywords[canonical] else {
                continue
            }
            if keywords.contains(where: { keyword in
                if keyword.count <= 1 {
                    return separatedTokens.contains { $0.caseInsensitiveCompare(keyword) == .orderedSame }
                }
                return value.contains(keyword)
            }) {
                tokens.append(canonical)
            }
        }
        return Array(Set(tokens))
    }

    private func parseOrientation(_ value: String) -> String? {
        for token in orientationTokens.sorted(by: { $0.count > $1.count }) {
            if value.contains(token) {
                return orientationAliases[token] ?? token
            }
        }
        return nil
    }

    private func materialDisplay(_ material: String?, original: String) -> String {
        guard let material else {
            return original.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let configured = materialDisplayNames[material.uppercased()] {
            return configured
        }
        return material
    }

    private func displayProcessingPrefix(_ processing: [String]) -> String {
        let parts = processing.sorted()
        if parts.isEmpty {
            return ""
        }
        return parts.joined(separator: " ") + " "
    }
}
