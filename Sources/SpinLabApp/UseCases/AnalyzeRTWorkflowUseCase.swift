import Foundation

// MARK: - RTAnalysisResult

/// Full RT curve extracted from a single RT measurement file.
/// Represents the RT workflow's analysis output (Rxx vs temperature).
struct RTAnalysisResult: Codable, Hashable, Sendable {
    let workflowID: String
    let sourceFilePath: String
    let sidecarPath: String?
    let device: String
    let conditions: [String: String]
    let temperatureK: [Double]
    let rxx: [Double]
    let warnings: [String]

    init(
        sourceFilePath: String,
        sidecarPath: String? = nil,
        device: String,
        conditions: [String: String] = [:],
        temperatureK: [Double],
        rxx: [Double],
        warnings: [String] = []
    ) {
        self.workflowID = WorkflowKey.rt.rawValue
        self.sourceFilePath = sourceFilePath
        self.sidecarPath = sidecarPath
        self.device = device
        self.conditions = conditions
        self.temperatureK = temperatureK
        self.rxx = rxx
        self.warnings = warnings
    }
}

// MARK: - AnalyzeRTWorkflowUseCase

/// Headless use case: parse a single RT measurement hit into an RTAnalysisResult.
///
/// Reads Col[0] (temperature K) and Col[9] (Rxx Ω) from the LVM file, sorts
/// ascending by temperature, and returns the curve with any parse warnings.
struct AnalyzeRTWorkflowUseCase {

    var parser = ThreeOmegaLVMParser()

    func execute(hit: WorkflowMeasurementSearchHit) -> RTAnalysisResult {
        let url = URL(fileURLWithPath: hit.measurementFilePath)
        let device = hit.conditions["device"] ?? hit.conditions["Device"] ?? ""
        var warnings: [String] = []

        do {
            let tempOverride = _parseConditionTemperatureK(hit.conditions["temperature"])
            let file = try parser.parse(
                fileURL: url,
                temperatureOverride: tempOverride,
                kindOverride: .rtSweep
            )
            guard !file.col0.isEmpty else {
                warnings.append("RT file has no data rows: \(url.lastPathComponent)")
                return RTAnalysisResult(
                    sourceFilePath: hit.measurementFilePath,
                    sidecarPath: hit.sidecarPath,
                    device: device,
                    conditions: hit.conditions,
                    temperatureK: [],
                    rxx: [],
                    warnings: warnings
                )
            }
            let pairs = zip(file.col0, file.col9).sorted { $0.0 < $1.0 }
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                device: device,
                conditions: hit.conditions,
                temperatureK: pairs.map { $0.0 },
                rxx: pairs.map { $0.1 },
                warnings: warnings
            )
        } catch {
            warnings.append("Failed to parse RT file [\(url.lastPathComponent)]: \(error.localizedDescription)")
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                device: device,
                conditions: hit.conditions,
                temperatureK: [],
                rxx: [],
                warnings: warnings
            )
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
