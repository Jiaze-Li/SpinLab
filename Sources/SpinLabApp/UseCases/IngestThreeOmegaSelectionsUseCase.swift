import Foundation

// MARK: - IngestThreeOmegaSelectionsUseCase
//
// Orchestrates parsing and fitting of a set of selected 3ω AHE measurement files.
// Separates field-sweep files from RT files, processes each, sorts by temperature,
// and produces a ThreeOmegaIngestionResult ready for display and scaling analysis.
//
// All display-facing parameters (device, temperature) are read from sidecar conditions
// confirmed at import time. The LVM parser provides fallback values only when sidecar
// conditions are absent (e.g. in unit tests with synthetic files).

struct IngestThreeOmegaSelectionsUseCase {

    var parser = ThreeOmegaLVMParser()
    var fitter = ThreeOmegaFitUseCase()

    /// Returns ingestion result for one device's worth of selected hits.
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
                device: "",
                warnings: ["No files selected."]
            )
        }

        var warnings: [String] = []
        var fieldSweeps: [ThreeOmegaFieldSweepResult] = []
        var rtFiles: [ThreeOmegaLVMFile] = []
        var device = ""
        var deviceValues: [String] = []
        var iRmsValues: [Double: Double] = [:]

        var seen = Set<String>()

        for hit in hits {
            guard seen.insert(hit.measurementFilePath).inserted else { continue }
            let url = URL(fileURLWithPath: hit.measurementFilePath)

            // Device (angle) from sidecar conditions — confirmed by user at import.
            let hitDevice = hit.conditions["device"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            do {
                let tempOverride = parseFile == nil
                    ? _parseConditionTemperatureK(hit.conditions["temperature"])
                    : nil
                let kindOverride: ThreeOmegaFileKind? = parseFile == nil
                    ? _parseKind(hit.workflowCanonicalID)
                    : nil
                let file = try (parseFile.map { try $0(url) } ?? parser.parse(fileURL: url, temperatureOverride: tempOverride, kindOverride: kindOverride))

                // Device priority: sidecar condition > parser fallback
                let resolvedDevice = hitDevice.isEmpty ? file.device : hitDevice
                if device.isEmpty { device = resolvedDevice }

                switch file.fileKind {
                case .fieldSweep:
                    let result = fitter.process(file: file, deviceOverride: resolvedDevice)
                    fieldSweeps.append(result)
                    iRmsValues[file.temperatureK] = file.iRms
                    if !hitDevice.isEmpty { deviceValues.append(hitDevice) }

                case .rtSweep:
                    rtFiles.append(file)
                }
            } catch {
                warnings.append("Parse failed [\(url.lastPathComponent)]: \(error.localizedDescription)")
            }
        }

        fieldSweeps.sort { $0.temperatureK < $1.temperatureK }

        let rtResult: ThreeOmegaRTResult? = {
            guard let best = rtFiles.max(by: { $0.col0.count < $1.col0.count }),
                  !best.col0.isEmpty else { return nil }
            if rtFiles.count > 1 {
                warnings.append("Multiple RT files found — using the one with most data rows (\(best.col0.count) pts, \(best.stem)).")
            }
            let pairs = zip(best.col0, best.col9).sorted { $0.0 < $1.0 }
            return ThreeOmegaRTResult(
                device: device,
                temperatureK: pairs.map { $0.0 },
                rxx: pairs.map { $0.1 }
            )
        }()

        // Detect mixed device values from sidecar conditions (field-sweep files only).
        let uniqueDevices = Set(deviceValues)
        if uniqueDevices.count > 1 {
            warnings.append("Mixed device angles detected (\(uniqueDevices.sorted().joined(separator: ", "))) — only the first device (\(device)) is used for analysis.")
        }

        if rtResult == nil {
            warnings.append("No RT files found among selections — Rxx(T) and Scaling Law unavailable.")
        }

        return ThreeOmegaIngestionResult(
            fieldSweeps: fieldSweeps,
            rtResult: rtResult,
            device: device,
            iRmsValues: iRmsValues,
            warnings: warnings
        )
    }

    // MARK: - Private

    private func _parseKind(_ canonicalID: String) -> ThreeOmegaFileKind? {
        switch canonicalID {
        case "rt":  return .rtSweep
        case "3w":  return .fieldSweep
        default:    return nil
        }
    }

    private func _parseConditionTemperatureK(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasSuffix("K") || trimmed.hasSuffix("k")
            ? String(trimmed.dropLast())
            : trimmed
        return Double(digits.trimmingCharacters(in: .whitespaces))
    }
}
