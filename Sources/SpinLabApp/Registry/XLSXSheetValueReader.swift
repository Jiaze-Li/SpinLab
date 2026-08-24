import CoreXLSX
import Foundation

enum XLSXSheetValueReader {
    static func headerValueByColumnIndex(row: Row, sharedStrings: SharedStrings?) -> [Int: String] {
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

    static func rowMetadata(
        row: Row,
        headerByColumn: [Int: String],
        sharedStrings: SharedStrings?,
        trimValues: Bool = true
    ) -> [String: String] {
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
            let normalizedValue = trimValues ? trimmed : value

            let key = headerByColumn[column] ?? "Column\(column)"
            metadata[key] = normalizedValue
        }
        return metadata
    }

    static func rowValue(row: Row, atColumn column: Int, sharedStrings: SharedStrings?) -> String? {
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

    /// Whether the cell at `column` is numerically typed (`type == nil` or
    /// `.number` — OOXML defaults an omitted `t` attribute to numeric) as
    /// opposed to a string/shared-string/inline-string cell. Lets a caller
    /// distinguish a genuine Excel date serial from Registry's own text
    /// date convention without reading styles/numFmt — see
    /// `RegistryGrowthDateMapper.semanticISODate(rawValue:isNumericCell:)`.
    /// Returns nil if no cell exists at `column` on this row.
    static func isNumericCell(row: Row, atColumn column: Int) -> Bool? {
        for cell in row.cells where columnIndex(for: cell) == column {
            switch cell.type {
            case nil, .number:
                return true
            default:
                return false
            }
        }
        return nil
    }

    static func cellString(cell: Cell, sharedStrings: SharedStrings?) -> String? {
        // `Cell.stringValue`/`Cell.value` only ever resolve a shared-string
        // index or a literal `<v>` value — neither touches `inlineString`,
        // so a cell written as `t="inlineStr"` (the format every writer in
        // this app uses — see `XLSXWorkbookKit.setCellValue`) would
        // otherwise read back as empty through CoreXLSX. Check it first:
        // an inlineStr cell never carries a shared-string index anyway.
        if cell.type == .inlineStr {
            return cell.inlineString?.text
        }
        if let sharedStrings {
            return cell.stringValue(sharedStrings)
        }
        return cell.value
    }

    static func columnIndex(for cell: Cell) -> Int? {
        columnIndex(from: cell.reference.column.value)
    }

    static func columnIndex(from columnLabel: String) -> Int? {
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
