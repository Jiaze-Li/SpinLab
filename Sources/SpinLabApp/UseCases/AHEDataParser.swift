import Foundation

struct AHEDataParser {
    func parse(fileURL: URL) throws -> PPMSParsedFile {
        let raw: String
        do {
            raw = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            guard let latin1 = try? String(contentsOf: fileURL, encoding: .isoLatin1) else {
                throw AppError.io("Cannot read file: \(fileURL.lastPathComponent)")
            }
            raw = latin1
        }

        let allLines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let columnLine: String
        let dataStartIndex: Int

        if allLines.first == "[Header]" {
            // Variant A: [Header] ... [Data] \n column-names \n rows
            guard let dataIdx = allLines.firstIndex(of: "[Data]") else {
                throw AppError.validation("Missing [Data] section: \(fileURL.lastPathComponent)")
            }
            let colIdx = dataIdx + 1
            guard colIdx < allLines.count, allLines[colIdx].hasPrefix("Comment,") else {
                throw AppError.validation("Missing column header after [Data]: \(fileURL.lastPathComponent)")
            }
            columnLine = allLines[colIdx]
            dataStartIndex = colIdx + 1
        } else if allLines.first?.hasPrefix("Comment,") == true {
            // Variant B: no [Header] block, file starts directly with column names
            columnLine = allLines[0]
            dataStartIndex = 1
        } else {
            throw AppError.validation("Unrecognized .dat format: \(fileURL.lastPathComponent)")
        }

        let columnNames = columnLine
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let colCount = columnNames.count
        let rows: [[String]] = allLines[dataStartIndex...]
            .filter { !$0.isEmpty }
            .map { line -> [String] in
                var fields = line
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if fields.count < colCount {
                    fields += Array(repeating: "", count: colCount - fields.count)
                } else if fields.count > colCount {
                    fields = Array(fields.prefix(colCount))
                }
                return fields
            }

        return PPMSParsedFile(columnNames: columnNames, rows: rows, sourceRef: fileURL.path)
    }
}
