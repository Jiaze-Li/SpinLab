import Foundation

// MARK: - RTMeasurementFormat

enum RTMeasurementFormat: String, Codable, Hashable, Sendable {
    case lvm
    case ppmsDat = "ppms-dat"
}

// MARK: - RTAnalysisResult

/// Full RT curve extracted from a single RT measurement file.
struct RTAnalysisResult: Codable, Hashable, Sendable {
    let workflowID: String
    let sourceFilePath: String
    let sidecarPath: String?
    let sampleKey: String
    let sampleID: String?
    let format: RTMeasurementFormat
    let channelID: String?
    let bridgeIndex: Int?
    let device: String
    let conditions: [String: String]
    /// Resolver-compatible metadata for Workbench legend auto-inference.
    /// Optional for backward-compatible decoding of older RT packs.
    let sampleMetadata: [String: String]?
    let temperatureK: [Double]
    let rxx: [Double]
    let warnings: [String]

    init(
        sourceFilePath: String,
        sidecarPath: String? = nil,
        sampleKey: String = "",
        sampleID: String? = nil,
        format: RTMeasurementFormat = .lvm,
        channelID: String? = nil,
        bridgeIndex: Int? = nil,
        device: String,
        conditions: [String: String] = [:],
        sampleMetadata: [String: String]? = nil,
        temperatureK: [Double],
        rxx: [Double],
        warnings: [String] = []
    ) {
        self.workflowID = WorkflowKey.rt.rawValue
        self.sourceFilePath = sourceFilePath
        self.sidecarPath = sidecarPath
        self.sampleKey = sampleKey
        self.sampleID = sampleID
        self.format = format
        self.channelID = channelID
        self.bridgeIndex = bridgeIndex
        self.device = device
        self.conditions = conditions
        self.sampleMetadata = sampleMetadata
        self.temperatureK = temperatureK
        self.rxx = rxx
        self.warnings = warnings
    }
}

// MARK: - AnalyzeRTWorkflowUseCase

/// Headless use case: parse a single RT measurement hit into an RTAnalysisResult.
///
/// Dispatches by file extension:
///   .dat  → RTPPMSDatParser (PPMS MultiVu)
///   .lvm  → ThreeOmegaLVMParser (3ω / LVM RT sweep)
struct AnalyzeRTWorkflowUseCase {

    var lvmParser = ThreeOmegaLVMParser()
    var datParser = RTPPMSDatParser()

    func execute(hit: WorkflowMeasurementSearchHit, numericDisplay: [String: String] = [:]) -> RTAnalysisResult {
        let url = URL(fileURLWithPath: hit.measurementFilePath)
        if url.pathExtension.lowercased() == "dat" {
            return _executePPMSDat(hit: hit, url: url, numericDisplay: numericDisplay)
        } else {
            return _executeLVM(hit: hit, url: url, numericDisplay: numericDisplay)
        }
    }

    // MARK: - PPMS .dat path

    private func _executePPMSDat(hit: WorkflowMeasurementSearchHit, url: URL, numericDisplay: [String: String]) -> RTAnalysisResult {
        let device = hit.conditions["device"] ?? hit.conditions["Device"] ?? ""
        let name = url.lastPathComponent
        let metadata = WorkbenchSeriesMetadataBuilder.build(from: hit, numericDisplay: numericDisplay)

        guard let channelID = hit.channels.first, !channelID.isEmpty else {
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                sampleKey: hit.sampleKey,
                format: .ppmsDat,
                device: device,
                conditions: hit.conditions,
                sampleMetadata: metadata,
                temperatureK: [],
                rxx: [],
                warnings: ["PPMS .dat entry '\(name)' has no channel metadata (ch1/ch2/ch3); bridge index cannot be determined"]
            )
        }

        guard let bridgeIdx = RTPPMSDatParser.bridgeIndex(forChannel: channelID) else {
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                sampleKey: hit.sampleKey,
                format: .ppmsDat,
                channelID: channelID,
                device: device,
                conditions: hit.conditions,
                sampleMetadata: metadata,
                temperatureK: [],
                rxx: [],
                warnings: ["Unrecognized channel '\(channelID)' in '\(name)'; expected ch1, ch2, or ch3"]
            )
        }

        do {
            let result = try datParser.parse(fileURL: url, bridgeIndex: bridgeIdx)
            let pairs = zip(result.temperatureK, result.rxx).sorted { $0.0 < $1.0 }
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                sampleKey: hit.sampleKey,
                format: .ppmsDat,
                channelID: channelID,
                bridgeIndex: bridgeIdx,
                device: device,
                conditions: hit.conditions,
                sampleMetadata: metadata,
                temperatureK: pairs.map { $0.0 },
                rxx: pairs.map { $0.1 },
                warnings: result.warnings
            )
        } catch {
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                sampleKey: hit.sampleKey,
                format: .ppmsDat,
                channelID: channelID,
                bridgeIndex: bridgeIdx,
                device: device,
                conditions: hit.conditions,
                sampleMetadata: metadata,
                temperatureK: [],
                rxx: [],
                warnings: ["Failed to parse PPMS .dat '\(name)': \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - LVM path (3ω RT sweep)

    private func _executeLVM(hit: WorkflowMeasurementSearchHit, url: URL, numericDisplay: [String: String]) -> RTAnalysisResult {
        let device = hit.conditions["device"] ?? hit.conditions["Device"] ?? ""
        let metadata = WorkbenchSeriesMetadataBuilder.build(from: hit, numericDisplay: numericDisplay)
        var warnings: [String] = []

        do {
            let tempOverride = _parseConditionTemperatureK(hit.conditions["temperature"])
            let file = try lvmParser.parse(
                fileURL: url,
                temperatureOverride: tempOverride,
                kindOverride: .rtSweep
            )
            guard !file.col0.isEmpty else {
                warnings.append("RT file has no data rows: \(url.lastPathComponent)")
                return RTAnalysisResult(
                    sourceFilePath: hit.measurementFilePath,
                    sidecarPath: hit.sidecarPath,
                    sampleKey: hit.sampleKey,
                    format: .lvm,
                    device: device,
                    conditions: hit.conditions,
                    sampleMetadata: metadata,
                    temperatureK: [],
                    rxx: [],
                    warnings: warnings
                )
            }
            let pairs = zip(file.col0, file.col9).sorted { $0.0 < $1.0 }
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                sampleKey: hit.sampleKey,
                format: .lvm,
                device: device,
                conditions: hit.conditions,
                sampleMetadata: metadata,
                temperatureK: pairs.map { $0.0 },
                rxx: pairs.map { $0.1 },
                warnings: warnings
            )
        } catch {
            warnings.append("Failed to parse RT file [\(url.lastPathComponent)]: \(error.localizedDescription)")
            return RTAnalysisResult(
                sourceFilePath: hit.measurementFilePath,
                sidecarPath: hit.sidecarPath,
                sampleKey: hit.sampleKey,
                format: .lvm,
                device: device,
                conditions: hit.conditions,
                sampleMetadata: metadata,
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
