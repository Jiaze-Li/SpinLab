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

    static func cellString(cell: Cell, sharedStrings: SharedStrings?) -> String? {
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
