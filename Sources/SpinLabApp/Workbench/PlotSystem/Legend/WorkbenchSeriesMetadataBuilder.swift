import Foundation

// MARK: - WorkbenchSeriesMetadataBuilder
//
// Shared builder for resolver-compatible plot series metadata.
//
// WorkbenchRenderPipeline can auto-resolve legend labels only when each
// WorkbenchPlotSeries carries metadata keyed by the dimensions understood by
// LegendDimensionResolver. This builder centralizes the conversion from library
// search-hit context into that metadata dictionary so new workflows do not have
// to duplicate or remember the implicit contract.

enum WorkbenchSeriesMetadataBuilder {

    /// Builds resolver-compatible metadata from a search hit.
    ///
    /// Substrate includes processing tokens (b, o, HF, etc.) + material + orientation
    /// so samples with the same material but different treatments are distinguished.
    ///
    /// - Parameter numericDisplay: Optional per-sample numeric display values from library index
    ///   (keys like "厚度", "温度", "氧压", "能量"). Mapped to resolver keys.
    static func build(
        from hit: WorkflowMeasurementSearchHit,
        numericDisplay: [String: String] = [:]
    ) -> [String: String] {
        var meta: [String: String] = [:]

        // Condition-level: test temperature, device.
        if let t = hit.conditions["temperature"] { meta["temperature"] = t }
        if let d = hit.conditions["device"], !d.isEmpty { meta["device"] = d }

        // SampleKey-level: substrate (processing tokens + material + orientation).
        if let descriptor = SampleSemanticDescriptor.fromSampleKey(hit.sampleKey) {
            // Prefer rule-set-normalized display tokens; fall back to raw key component
            // so unregistered tokens (e.g. "o", "b") still distinguish series in the legend.
            let treatment: String
            if !descriptor.processingTokens.isEmpty {
                treatment = descriptor.processingTokens.sorted().joined(separator: "+")
            } else {
                let keyParts = hit.sampleKey
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map(String.init)
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

        // NumericTags-level: energy, pressure, growth temperature, thickness.
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
                // Growth temperature from registry — distinct from test temperature.
                meta["growthTemperature"] = value
            }
        }

        meta["sampleKey"] = hit.sampleKey
        meta["batchID"] = hit.batchID
        return meta
    }
}
