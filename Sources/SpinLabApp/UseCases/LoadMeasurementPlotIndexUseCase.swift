import Foundation

struct LoadMeasurementPlotIndexUseCase {
    let pathResolver: LibraryPathResolver

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Returns the `MeasurementPlotIndex` for `sampleKey`, or nil if the file is absent,
    /// unreadable, contains corrupt JSON, or carries an unrecognized schema version (≠ 1).
    ///
    /// Never throws — fail-soft per Adj-10.
    /// Missing file → nil (silent). Decode failure or unknown schema → fputs stderr + nil.
    func execute(sampleKey: String) -> MeasurementPlotIndex? {
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_plot_index.json"
        guard let url = try? pathResolver.absoluteURL(for: relPath) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsErr = error as NSError
            if nsErr.domain != NSCocoaErrorDomain || nsErr.code != NSFileReadNoSuchFileError {
                fputs("[SpinLab] LoadMeasurementPlotIndex: read error for \(sampleKey): \(error)\n", stderr)
            }
            return nil
        }
        guard let index = try? Self.decoder.decode(MeasurementPlotIndex.self, from: data) else {
            fputs("[SpinLab] LoadMeasurementPlotIndex: JSON decode failed for \(sampleKey)\n", stderr)
            return nil
        }
        guard index.schemaVersion == 1 else {
            fputs("[SpinLab] LoadMeasurementPlotIndex: unsupported schema v\(index.schemaVersion) for \(sampleKey)\n", stderr)
            return nil
        }
        return index
    }
}
