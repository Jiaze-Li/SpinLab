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
        var rtTemps: [Double] = []
        var rtRxx: [Double] = []
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
                    // RT file: col0 = temperature (K), col9 = Rxx (Ω)
                    // Formula: Rxx(T) = Col[9]  (pre-calculated R_H = longitudinal Rxx in RT geometry)
                    // Merge multiple RT files by appending (sorted later)
                    rtTemps.append(contentsOf: file.col0)
                    rtRxx.append(contentsOf: file.col9)
                }
            } catch {
                warnings.append("Parse failed [\(url.lastPathComponent)]: \(error.localizedDescription)")
            }
        }

        // Sort field sweeps by temperature ascending
        fieldSweeps.sort { $0.temperatureK < $1.temperatureK }

        // Build RT result if we have RT data
        let rtResult: ThreeOmegaRTResult? = rtTemps.isEmpty ? nil : {
            // Sort RT data by temperature
            let pairs = zip(rtTemps, rtRxx).sorted { $0.0 < $1.0 }
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
