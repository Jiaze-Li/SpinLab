import Foundation

// MARK: - IngestThreeOmegaSelectionsUseCase
//
// Orchestrates parsing and fitting of a set of selected 3ω AHE measurement files.
// Separates field-sweep files from RT files, processes each, sorts by temperature,
// and produces a ThreeOmegaIngestionResult ready for display and scaling analysis.

struct IngestThreeOmegaSelectionsUseCase {

    var parser = ThreeOmegaLVMParser()
    var fitter = ThreeOmegaFitUseCase()

    /// Returns ingestion result for one angle's worth of selected hits.
    /// All hits are expected to belong to the same angle folder.
    ///
    /// - Parameter parseFile: Injectable for testing. Defaults to real LVM parser.
    func execute(
        hits: [WorkflowMeasurementSearchHit],
        parseFile: ((URL) throws -> ThreeOmegaLVMFile)? = nil
    ) -> ThreeOmegaIngestionResult {
        guard !hits.isEmpty else {
            return ThreeOmegaIngestionResult(
                fieldSweeps: [],
                rtResult: nil,
                angleLabel: "",
                warnings: ["No files selected."]
            )
        }

        let parseImpl: (URL) throws -> ThreeOmegaLVMFile = parseFile ?? { [parser] url in
            try parser.parse(fileURL: url)
        }

        var warnings: [String] = []
        var fieldSweeps: [ThreeOmegaFieldSweepResult] = []
        var rtFiles: [ThreeOmegaLVMFile] = []   // collect all RT files; pick best at end
        var angleLabel = ""
        var iRmsValues: [Double: Double] = [:]

        // Parse each unique file exactly once (deduplicate by sourceFilePath)
        var seen = Set<String>()

        for hit in hits {
            guard seen.insert(hit.sourceFilePath).inserted else { continue }
            let url = URL(fileURLWithPath: hit.sourceFilePath)

            do {
                let file = try parseImpl(url)
                if angleLabel.isEmpty { angleLabel = file.angleLabel }

                switch file.fileKind {
                case .fieldSweep:
                    let result = fitter.process(file: file)
                    fieldSweeps.append(result)
                    iRmsValues[file.temperatureK] = file.iRms

                case .rtSweep:
                    // Collect all RT files; select the best one after the loop.
                    rtFiles.append(file)
                }
            } catch {
                warnings.append("Parse failed [\(url.lastPathComponent)]: \(error.localizedDescription)")
            }
        }

        // Sort field sweeps by temperature ascending
        fieldSweeps.sort { $0.temperatureK < $1.temperatureK }

        // Build RT result: pick the RT file with the most data rows.
        // Rationale: when multiple RT files exist (e.g. one aborted at 1 row and one
        // complete at 30 rows), the longest file is the real RT curve.
        let rtResult: ThreeOmegaRTResult? = {
            guard let best = rtFiles.max(by: { $0.col0.count < $1.col0.count }),
                  !best.col0.isEmpty else { return nil }
            if rtFiles.count > 1 {
                warnings.append("Multiple RT files found — using the one with most data rows (\(best.col0.count) pts, \(best.stem)).")
            }
            let pairs = zip(best.col0, best.col9).sorted { $0.0 < $1.0 }
            return ThreeOmegaRTResult(
                angleLabel: angleLabel,
                temperatureK: pairs.map { $0.0 },
                rxx: pairs.map { $0.1 }
            )
        }()

        if rtResult == nil {
            warnings.append("No RT files found among selections — Rxx(T) and Fig 5b scaling unavailable.")
        }

        return ThreeOmegaIngestionResult(
            fieldSweeps: fieldSweeps,
            rtResult: rtResult,
            angleLabel: angleLabel,
            iRmsValues: iRmsValues,
            warnings: warnings
        )
    }
}
