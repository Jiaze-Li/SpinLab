import Foundation

// MARK: - WP2 — standard table Dataset (`measurement_table_v1`)
//
// One faithful, workflow-neutral encoding of a `LoadedMeasurement`: every column in file order with
// its label, unit, quantity tag and the loader diagnostics, values as column-major IEEE 754
// Float64 (little endian, NaN bit patterns preserved). No scientific interpretation lives here:
// what a column *means* (channels, harmonics, Rxy) stays in workflow code (K12).
// Measurement context is never written into the Dataset (K7).

struct MeasurementTableCodec: DatasetPayloadCodec {
    static let format = "measurement_table_v1"
    static let codecVersion = 1
    static let columnsFile = "columns.json"
    static let valuesFile = "values.bin"

    var datasetFormat: String { Self.format }

    // MARK: Stored form

    struct StoredUnit: Codable, Equatable {
        /// `magneticField`, `temperature`, `current`, `raw`, `undeclared`.
        let kind: String
        let value: String?
    }

    struct StoredColumn: Codable, Equatable {
        let stableSourceKey: String
        let sourceColumnIndex: Int
        let rawLabel: String?
        let unit: StoredUnit
        let physicalQuantityID: String?
        let instrumentChannelLabel: String?
    }

    struct StoredDiagnostic: Codable, Equatable {
        let code: String
        let message: String
        let columnKey: String?
        let rowIndex: Int?
    }

    struct StoredTable: Codable, Equatable {
        let codecVersion: Int
        let loaderFormat: String
        let rowCount: Int
        let columns: [StoredColumn]
        let diagnostics: [StoredDiagnostic]
    }

    enum CodecError: Error, Equatable {
        case unsupportedVersion(Int)
        case unknownLoaderFormat(String)
        case unknownUnit(kind: String, value: String?)
        case unknownQuantity(String)
        case valuesSizeMismatch(expected: Int, actual: Int)
        case invalidShape(String)
    }

    // MARK: Encode

    static func encode(_ measurement: LoadedMeasurement) throws -> StandardizedDatasetContent {
        guard !measurement.signals.isEmpty else { throw CodecError.invalidShape("no columns") }
        for column in measurement.signals where column.values.count != measurement.rowCount {
            throw CodecError.invalidShape("column '\(column.stableSourceKey)' has \(column.values.count) values, expected \(measurement.rowCount)")
        }
        let stored = StoredTable(
            codecVersion: codecVersion,
            loaderFormat: measurement.format.rawValue,
            rowCount: measurement.rowCount,
            columns: measurement.signals.map { column in
                StoredColumn(
                    stableSourceKey: column.stableSourceKey, sourceColumnIndex: column.sourceColumnIndex,
                    rawLabel: column.rawLabel, unit: storedUnit(column.sourceUnit),
                    physicalQuantityID: column.physicalQuantityID?.rawValue,
                    instrumentChannelLabel: column.instrumentChannelLabel
                )
            },
            diagnostics: measurement.diagnostics.map {
                StoredDiagnostic(code: $0.code, message: $0.message, columnKey: $0.columnKey, rowIndex: $0.rowIndex)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var bytes = Data(capacity: measurement.signals.count * measurement.rowCount * 8)
        for column in measurement.signals {
            for value in column.values {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
            }
        }
        return StandardizedDatasetContent(format: format, files: [
            StandardizedFile(name: columnsFile, data: try encoder.encode(stored)),
            StandardizedFile(name: valuesFile, data: bytes)
        ])
    }

    // MARK: Decode

    func decode(files: [String: Data]) throws -> LoadedMeasurement {
        guard let columnsData = files[Self.columnsFile], let valuesData = files[Self.valuesFile] else {
            throw CodecError.invalidShape("columns.json or values.bin is missing")
        }
        let stored = try JSONDecoder().decode(StoredTable.self, from: columnsData)
        guard stored.codecVersion == Self.codecVersion else { throw CodecError.unsupportedVersion(stored.codecVersion) }
        guard let format = MeasurementFileFormat(rawValue: stored.loaderFormat) else {
            throw CodecError.unknownLoaderFormat(stored.loaderFormat)
        }
        guard !stored.columns.isEmpty, stored.rowCount >= 0 else { throw CodecError.invalidShape("no columns") }
        let (cells, overflow) = stored.columns.count.multipliedReportingOverflow(by: stored.rowCount)
        let expected = cells.multipliedReportingOverflow(by: 8)
        guard !overflow, !expected.overflow else { throw CodecError.invalidShape("table dimensions overflow") }
        guard valuesData.count == expected.partialValue else {
            throw CodecError.valuesSizeMismatch(expected: expected.partialValue, actual: valuesData.count)
        }
        var columns: [MeasurementColumn] = []
        for (index, column) in stored.columns.enumerated() {
            var values = [Double](); values.reserveCapacity(stored.rowCount)
            let base = index * stored.rowCount * 8
            for row in 0..<stored.rowCount {
                let offset = base + row * 8
                var bits: UInt64 = 0
                for byte in 0..<8 { bits |= UInt64(valuesData[valuesData.startIndex + offset + byte]) << (8 * UInt64(byte)) }
                values.append(Double(bitPattern: bits))
            }
            var quantity: PhysicalQuantityID?
            if let raw = column.physicalQuantityID {
                guard let known = PhysicalQuantityID(rawValue: raw) else { throw CodecError.unknownQuantity(raw) }
                quantity = known
            }
            columns.append(MeasurementColumn(
                stableSourceKey: column.stableSourceKey, rawLabel: column.rawLabel,
                sourceColumnIndex: column.sourceColumnIndex, values: values,
                sourceUnit: try Self.unit(column.unit), physicalQuantityID: quantity,
                instrumentChannelLabel: column.instrumentChannelLabel
            ))
        }
        return LoadedMeasurement(
            sourceFilePath: "", format: format, signals: columns, rowCount: stored.rowCount,
            diagnostics: stored.diagnostics.map {
                MeasurementDiagnostic(code: $0.code, message: $0.message, columnKey: $0.columnKey, rowIndex: $0.rowIndex)
            }
        )
    }

    // MARK: Unit mapping (explicit and reversible; an unknown value fails instead of becoming "undeclared")

    static func storedUnit(_ tag: PhysicalQuantityUnitTag) -> StoredUnit {
        switch tag {
        case let .magneticField(unit): return StoredUnit(kind: "magneticField", value: unit.rawValue)
        case let .temperature(unit): return StoredUnit(kind: "temperature", value: unit.rawValue)
        case let .current(unit): return StoredUnit(kind: "current", value: unit.rawValue)
        case let .raw(text): return StoredUnit(kind: "raw", value: text)
        case .undeclared: return StoredUnit(kind: "undeclared", value: nil)
        }
    }

    static func unit(_ stored: StoredUnit) throws -> PhysicalQuantityUnitTag {
        switch (stored.kind, stored.value) {
        case let ("magneticField", value?):
            guard let unit = MagneticFieldUnit(rawValue: value) else { throw CodecError.unknownUnit(kind: stored.kind, value: value) }
            return .magneticField(unit)
        case let ("temperature", value?):
            guard let unit = TemperatureUnit(rawValue: value) else { throw CodecError.unknownUnit(kind: stored.kind, value: value) }
            return .temperature(unit)
        case let ("current", value?):
            guard let unit = CurrentUnit(rawValue: value) else { throw CodecError.unknownUnit(kind: stored.kind, value: value) }
            return .current(unit)
        case let ("raw", value?): return .raw(value)
        case ("undeclared", nil): return .undeclared
        default: throw CodecError.unknownUnit(kind: stored.kind, value: stored.value)
        }
    }
}
