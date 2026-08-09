import Foundation

/// Thin interpretation adapter over `RSMTextLoader` (Phase 3i RSM migration). All raw RSM text
/// grammar — comment skipping, header detection, H/K/L/detector column resolution, whitespace
/// parsing, numeric conversion — lives in `RSMTextLoader`; this type only reassembles its
/// column-major `LoadedMeasurement` output into RSM's row-of-points workflow type,
/// `CanonicalRSMDataset`. Kept (rather than deleted) because `CanonicalRSMDataset`/`RSMView`
/// consumers and existing tests are written against a `parse(text:) -> CanonicalRSMDataset`
/// entry point; deleting it would mean re-deriving that shape at every call site instead of once,
/// here.
///
/// `ParseError` is a typealias, not a second error type: it is `RSMTextLoader.LoadError` under
/// this type's pre-migration name, so `#expect(throws: RSMDataParser.ParseError.self)` call sites
/// keep working unchanged against errors actually thrown by `RSMTextLoader`.
enum RSMDataParser {

    typealias ParseError = RSMTextLoader.LoadError

    static func parse(
        text: String,
        title: String = "",
        sourceRef: String = ""
    ) throws -> CanonicalRSMDataset {
        let measurement = try RSMTextLoader.parseMeasurement(text: text, sourceFilePath: sourceRef)
        return interpret(measurement, title: title, sourceRef: sourceRef)
    }

    /// Reassembles a `LoadedMeasurement` produced by `RSMTextLoader` (from either `parse(text:)`
    /// above or `RSMTextLoader.load(fileURL:)`) into `CanonicalRSMDataset`. Pure column -> point
    /// transposition; no grammar knowledge.
    static func interpret(
        _ measurement: LoadedMeasurement,
        title: String,
        sourceRef: String
    ) -> CanonicalRSMDataset {
        func column(_ key: String) -> MeasurementColumn {
            measurement.signals.first { $0.stableSourceKey == key }!
        }
        let h = column("H").values
        let k = column("K").values
        let l = column("L").values
        let detectorColumn = column("detector")
        let d = detectorColumn.values

        var points: [CanonicalRSMPoint] = []
        points.reserveCapacity(measurement.rowCount)
        for i in 0..<measurement.rowCount {
            points.append(CanonicalRSMPoint(h: h[i], k: k[i], l: l[i], detector: d[i]))
        }

        let detectorColumnName = (detectorColumn.rawLabel ?? "Detector").capitalized

        return CanonicalRSMDataset(
            points: points,
            title: title,
            sourceRef: sourceRef,
            detectorColumnName: detectorColumnName
        )
    }
}
