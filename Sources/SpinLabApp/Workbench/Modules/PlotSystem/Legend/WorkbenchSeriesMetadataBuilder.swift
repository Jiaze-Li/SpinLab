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

    /// Canonical resolver-facing dimension keys this builder can emit.
    /// Kept in sync with `LegendDimensionResolver.defaultChain`.
    static let canonicalDimensionKeys: [String] = [
        "temperature", "field", "device", "harmonic", "substrate",
        "energy", "pressure", "growthTemperature", "thickness",
    ]

    /// Builds resolver-compatible metadata for a *derived-result* workflow — one whose
    /// plot series no longer originate from a single `WorkflowMeasurementSearchHit`
    /// (e.g. Scaling vs Angle, aggregate analyses, plots of previously-computed results).
    ///
    /// Derived workflows must funnel their canonical semantic metadata through this
    /// entry point rather than hand-rolling a `[String: String]`, so every workflow —
    /// regardless of data origin — produces the same `LegendResolver`-compatible
    /// vocabulary. Only non-nil, non-empty values are emitted.
    ///
    /// Internal identity / provenance (UUID, runID, candidateID, sourceID, sampleKey|run)
    /// must NEVER be passed here as a canonical dimension — it is not user-visible legend
    /// semantics. `sampleKey` is accepted only as bookkeeping (not a chain dimension).
    static func buildDerived(
        sampleKey: String? = nil,
        temperature: String? = nil,
        field: String? = nil,
        device: String? = nil,
        harmonic: String? = nil,
        substrate: String? = nil,
        energy: String? = nil,
        pressure: String? = nil,
        growthTemperature: String? = nil,
        thickness: String? = nil
    ) -> [String: String] {
        var meta: [String: String] = [:]
        func put(_ key: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            meta[key] = value
        }
        put("temperature", temperature)
        put("field", field)
        put("device", device)
        put("harmonic", harmonic)
        put("substrate", substrate)
        put("energy", energy)
        put("pressure", pressure)
        put("growthTemperature", growthTemperature)
        put("thickness", thickness)
        put("sampleKey", sampleKey)
        return meta
    }
}
