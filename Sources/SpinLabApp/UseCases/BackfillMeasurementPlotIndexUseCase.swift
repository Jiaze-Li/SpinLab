import Foundation

/// One-time backfill: rebuilds `MeasurementPlotIndex` from existing manifest files
/// when the index JSON does not yet exist for a sample (e.g. charts generated before v4.1.2.17).
///
/// After a successful backfill the index is written to disk so subsequent loads are fast.
/// Fail-soft per Adj-10: any unreadable manifest is skipped; the index is still written with
/// whatever entries could be recovered.
struct BackfillMeasurementPlotIndexUseCase {
    let pathResolver: LibraryPathResolver

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Reads every manifest referenced in `results`, builds a `MeasurementPlotIndex`,
    /// writes it to disk, and returns it.  Returns nil only if nothing could be written.
    @discardableResult
    func execute(sampleKey: String, results: WorkbenchResultsIndex) -> MeasurementPlotIndex? {
        var index = MeasurementPlotIndex(sampleKey: sampleKey, updatedAt: Date())

        for ref in results.references {
            guard let manifestURL = try? pathResolver.absoluteURL(for: ref.manifestPath),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? Self.decoder.decode(WorkbenchRunManifest.self, from: data)
            else {
                fputs("[SpinLab] BackfillMeasurementPlotIndex: skipping unreadable manifest \(ref.manifestPath)\n", stderr)
                continue
            }
            for inputFile in manifest.inputFiles {
                index.upsert(chartIdentityKey: ref.chartIdentityKey, sourceFile: inputFile)
            }
        }

        // Write to disk so future loads are fast.
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_plot_index.json"
        if let url = try? pathResolver.absoluteURL(for: relPath),
           let data = try? Self.encoder.encode(index) {
            try? data.write(to: url)
        } else {
            fputs("[SpinLab] BackfillMeasurementPlotIndex: could not write index for \(sampleKey)\n", stderr)
        }

        return index
    }
}
