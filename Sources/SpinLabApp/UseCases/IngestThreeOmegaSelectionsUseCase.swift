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
        rtHit: WorkflowMeasurementSearchHit? = nil,
        numericDisplayBySample: [String: [String: String]] = [:],
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

                switch file.fileKind {
                case .fieldSweep:
                    if device.isEmpty { device = resolvedDevice }
                    var result = fitter.process(file: file, deviceOverride: resolvedDevice)
                    result.sampleID = "\(hit.sampleKey)#\(result.temperatureK)"
                    result.sampleMetadata = Self._buildSampleMetadata(
                        from: hit,
                        numericDisplay: numericDisplayBySample[hit.sampleKey] ?? [:]
                    )
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

        // RAHE(1ω) HFE/WA divergence check
        for sweep in fieldSweeps {
            if let hfe = sweep.rahe1omega, let wa = sweep.rahe1omegaWA, abs(hfe) > 1e-30 {
                let pct = abs(hfe - wa) / abs(hfe) * 100
                if pct > 20 {
                    warnings.append(String(format: "T=%dK: RAHE(1ω) HFE/WA diverge by %.1f%%", Int(sweep.temperatureK), pct))
                }
            }
        }

        // RT file: prefer dedicated rtHit (user-selected), fall back to auto-detected from hits.
        let rtResult: ThreeOmegaRTResult? = {
            if let rtHit {
                let url = URL(fileURLWithPath: rtHit.measurementFilePath)
                do {
                    let tempOverride = parseFile == nil
                        ? _parseConditionTemperatureK(rtHit.conditions["temperature"])
                        : nil
                    let file = try (parseFile.map { try $0(url) } ?? parser.parse(fileURL: url, temperatureOverride: tempOverride, kindOverride: .rtSweep))
                    guard !file.col0.isEmpty else {
                        warnings.append("Dedicated RT file has no data rows: \(url.lastPathComponent)")
                        return nil
                    }
                    let pairs = zip(file.col0, file.col9).sorted { $0.0 < $1.0 }
                    return ThreeOmegaRTResult(
                        device: device,
                        temperatureK: pairs.map { $0.0 },
                        rxx: pairs.map { $0.1 }
                    )
                } catch {
                    warnings.append("Failed to parse dedicated RT file [\(url.lastPathComponent)]: \(error.localizedDescription)")
                    return nil
                }
            }

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

    /// Builds resolver-compatible metadata from a search hit.
    /// Substrate includes processing tokens (b, o, HF, etc.) + material + orientation
    /// so that samples with the same material but different treatments are distinguished.
    ///
    /// - Parameter numericDisplay: Optional per-sample numeric display values from library index
    ///   (keys like "厚度", "温度", "氧压", "能量"). Mapped to resolver keys.
    static func _buildSampleMetadata(
        from hit: WorkflowMeasurementSearchHit,
        numericDisplay: [String: String] = [:]
    ) -> [String: String] {
        var meta: [String: String] = [:]

        // Condition-level: test temperature, device
        if let t = hit.conditions["temperature"] { meta["temperature"] = t }
        if let d = hit.conditions["device"], !d.isEmpty { meta["device"] = d }

        // SampleKey-level: substrate (processing tokens + material + orientation)
        if let descriptor = SampleSemanticDescriptor.fromSampleKey(hit.sampleKey) {
            // Prefer rule-set-normalized display tokens; fall back to raw key component
            // so unregistered tokens (e.g. "o", "b") still distinguish series in the legend.
            let treatment: String
            if !descriptor.processingTokens.isEmpty {
                treatment = descriptor.processingTokens.sorted().joined(separator: "+")
            } else {
                let keyParts = hit.sampleKey.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                treatment = keyParts.count >= 2 ? keyParts[1] : ""
            }
            let material = descriptor.material ?? ""
            let orientation = descriptor.orientation ?? ""
            let parts = [treatment, material, orientation]
                .filter { !$0.isEmpty }
            let computed = parts.joined(separator: " ")
            if !computed.isEmpty {
                meta["substrate"] = computed
            } else if !hit.sampleSubstrate.isEmpty {
                meta["substrate"] = hit.sampleSubstrate
            }
        } else if !hit.sampleSubstrate.isEmpty {
            meta["substrate"] = hit.sampleSubstrate
        }

        // NumericTags-level: energy, pressure, growth temperature, thickness
        // Keys in numericDisplay are Chinese column headers from registry XLSX.
        for (chineseKey, value) in numericDisplay {
            let lower = chineseKey.lowercased()
            if lower.contains("能量") || lower.contains("energy") {
                meta["energy"] = value
            } else if lower.contains("氧压") || lower.contains("pressure") {
                meta["pressure"] = value
            } else if lower.contains("厚度") || lower.contains("thickness") {
                meta["thickness"] = value
            } else if lower.contains("温度") || lower.contains("temperature") {
                // Growth temperature from registry — distinct from test temperature
                meta["growthTemperature"] = value
            }
        }

        meta["sampleKey"] = hit.sampleKey
        meta["batchID"] = hit.batchID
        return meta
    }
}
