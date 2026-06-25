import Foundation

// MARK: - IngestIVSelectionsUseCase
//
// Converts selected search hits into an IVIngestionResult.
// Parses LVM files via IVLVMParser, then auto-detects ch1/ch2 dominant component
// by comparing median(|X|) vs median(|Y|) across all sweeps.

struct IngestIVSelectionsUseCase {

    func execute(hits: [WorkflowMeasurementSearchHit],
                 numericDisplayBySample: [String: [String: String]] = [:]) -> IVIngestionResult {
        guard !hits.isEmpty else {
            return IVIngestionResult(warnings: ["No files selected."])
        }

        var seen = Set<String>()
        let uniqueHits = hits
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
            .filter { seen.insert($0.measurementFilePath).inserted }

        var sweeps: [IVSweep] = []
        var warnings: [String] = []
        var devices = Set<String>()

        for hit in uniqueHits {
            let url = URL(fileURLWithPath: hit.measurementFilePath)

            let temperatureK: Double? = hit.conditions["temperature"]
                .flatMap { _parseTemperatureValue($0) }
            let fieldT: Double? = hit.conditions["field"]
                .flatMap { Double($0) }

            if let d = hit.conditions["device"], !d.isEmpty {
                devices.insert(d)
            }

            do {
                var sweep = try IVLVMParser().parse(
                    fileURL: url,
                    temperatureOverride: temperatureK,
                    fieldOverride: fieldT
                )
                sweep.sampleMetadata = _buildSampleMetadata(
                    from: hit,
                    numericDisplay: numericDisplayBySample[hit.sampleKey] ?? [:]
                )
                sweeps.append(sweep)
            } catch {
                let stem = url.deletingPathExtension().lastPathComponent
                warnings.append("Parse failed for \(stem): \(error.localizedDescription)")
            }
        }

        sweeps.sort(by: { $0.temperatureK < $1.temperatureK })

        let device: String
        if devices.count > 1 {
            warnings.append("Mixed devices: \(devices.sorted().joined(separator: ", ")). Using first.")
            device = devices.sorted().first ?? ""
        } else {
            device = devices.first ?? ""
        }

        let ch1State = _computeChannelState(
            x: sweeps.flatMap { $0.ch1X },
            y: sweeps.flatMap { $0.ch1Y }
        )
        let ch2State = _computeChannelState(
            x: sweeps.flatMap { $0.ch2X },
            y: sweeps.flatMap { $0.ch2Y }
        )

        return IVIngestionResult(
            sweeps: sweeps,
            device: device,
            warnings: warnings,
            ch1State: ch1State,
            ch2State: ch2State
        )
    }

    // MARK: - Channel mapping

    /// Computes dominant component from pooled X/Y samples across all sweeps.
    func _computeChannelState(x: [Double], y: [Double]) -> IVChannelState {
        let scoreX = _median(x.map { abs($0) })
        let scoreY = _median(y.map { abs($0) })
        let maxScore = max(scoreX, scoreY)
        let minScore = min(scoreX, scoreY)
        let confidence = minScore > 0 ? maxScore / minScore : 1.0
        let autoComponent: IVSignalComponent = scoreX >= scoreY ? .x : .y
        return IVChannelState(autoComponent: autoComponent, confidence: confidence)
    }

    // MARK: - Private helpers

    private func _parseTemperatureValue(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "K", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }

    private func _buildSampleMetadata(from hit: WorkflowMeasurementSearchHit,
                                      numericDisplay: [String: String]) -> [String: String] {
        var meta = WorkbenchSeriesMetadataBuilder.build(
            from: hit,
            numericDisplay: numericDisplay
        )

        if let temperature = hit.conditions["temperature"], !temperature.isEmpty {
            meta["temperature"] = temperature
        }
        if let device = _parseDevice(from: hit) {
            meta["device"] = device
        }
        if let field = _parseField(from: hit) {
            meta["field"] = field
        }
        return meta
    }

    private func _parseDevice(from hit: WorkflowMeasurementSearchHit) -> String? {
        if let device = hit.conditions["device"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !device.isEmpty {
            return device
        }
        if let angle = hit.conditions["angle"] ?? hit.conditions["phi"],
           let normalized = _normalizeAngleToken(angle) {
            return normalized
        }
        return _extractToken(
            from: hit.measurementFilePath,
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*deg"#
        ) { "\($0)deg" }
    }

    private func _parseField(from hit: WorkflowMeasurementSearchHit) -> String? {
        if let field = hit.conditions["field"], let normalized = _normalizeFieldToken(field) {
            return normalized
        }
        return _extractToken(
            from: hit.measurementFilePath,
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*T"#
        ) { "\($0)T" }
    }

    private func _extractToken(
        from path: String?,
        pattern: String,
        normalizer: (String) -> String
    ) -> String? {
        guard let path, !path.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, options: [], range: range),
              let tokenRange = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return normalizer(String(path[tokenRange]))
    }

    private func _normalizeAngleToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("deg") {
            let numberPart = trimmed.dropLast(3).trimmingCharacters(in: .whitespaces)
            return numberPart.isEmpty ? nil : "\(numberPart)deg"
        }
        if Double(trimmed) != nil {
            return "\(trimmed)deg"
        }
        return trimmed
    }

    private func _normalizeFieldToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("t") {
            let numberPart = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            return numberPart.isEmpty ? nil : "\(numberPart)T"
        }
        if Double(trimmed) != nil {
            return "\(trimmed)T"
        }
        return trimmed
    }

    private func _median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 0
            ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2
            : sorted[n / 2]
    }
}
