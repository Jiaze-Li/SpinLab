import Foundation

// MARK: - IngestXYRotationSelectionsUseCase
//
// Dispatches selected search hits to XYRotationLVMParser or XYRotationDATParser
// based on file extension, collects angle sweeps, and returns a sorted result.

struct IngestXYRotationSelectionsUseCase {

    func execute(hits: [WorkflowMeasurementSearchHit], numericDisplayBySample: [String: [String: String]] = [:]) -> XYRotationIngestionResult {
        guard !hits.isEmpty else {
            return XYRotationIngestionResult(warnings: ["No files selected."])
        }

        // Deduplicate by file path, stable sort by path
        var seen = Set<String>()
        let uniqueHits = hits
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
            .filter { seen.insert($0.measurementFilePath).inserted }

        var sweeps: [XYRotationAngleSweep] = []
        var warnings: [String] = []
        var devices = Set<String>()

        for hit in uniqueHits {
            let url = URL(fileURLWithPath: hit.measurementFilePath)
            let ext = url.pathExtension.lowercased()

            // Temperature override from sidecar condition
            let tempOverride: Double? = hit.conditions["temperature"]
                .flatMap { _parseTemperatureValue($0) }

            // φ offset from sidecar condition "shift" (value may contain suffix like "90shift")
            let shiftOverride: Double = hit.conditions["shift"]
                .flatMap { _parseLeadingNumber($0) } ?? 0

            // Device from sidecar condition
            if let d = hit.conditions["device"], !d.isEmpty {
                devices.insert(d)
            }

            do {
                var sweep: XYRotationAngleSweep
                switch ext {
                case "lvm":
                    sweep = try XYRotationLVMParser().parse(
                        fileURL: url,
                        temperatureOverride: tempOverride
                    )
                case "dat":
                    sweep = try XYRotationDATParser().parse(
                        fileURL: url,
                        temperatureOverride: tempOverride
                    )
                default:
                    warnings.append("Skipped unsupported file: \(url.lastPathComponent)")
                    continue
                }
                sweep.defaultPhiOffset = shiftOverride
                sweep.measurementFilePath = hit.measurementFilePath
                sweep.sampleMetadata = IngestThreeOmegaSelectionsUseCase._buildSampleMetadata(
                    from: hit,
                    numericDisplay: numericDisplayBySample[hit.sampleKey] ?? [:]
                )
                sweeps.append(sweep)
            } catch {
                warnings.append("Parse failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Sort by temperature ascending
        sweeps.sort(by: { $0.temperatureK < $1.temperatureK })

        // Device: take first, warn if mixed
        let device: String
        if devices.count > 1 {
            warnings.append("Mixed devices detected: \(devices.sorted().joined(separator: ", ")). Using first.")
            device = devices.sorted().first ?? ""
        } else {
            device = devices.first ?? ""
        }

        return XYRotationIngestionResult(
            sweeps: sweeps,
            device: device,
            warnings: warnings
        )
    }

    // MARK: - Private helpers

    /// Parse a temperature string like "80", "170.5K", "293 K" into a Double.
    private func _parseTemperatureValue(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "K", with: "")
            .replacingOccurrences(of: "k", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }

    /// Extracts the leading number from a string like "90shift" → 90.0, "-45.5shift" → -45.5.
    private func _parseLeadingNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"^(-?\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range(at: 1), in: trimmed) else { return nil }
        return Double(trimmed[range])
    }
}
