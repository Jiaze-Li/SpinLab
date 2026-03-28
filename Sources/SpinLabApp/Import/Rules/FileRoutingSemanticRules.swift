import Foundation

struct FileRoutingSemanticRules {
    var treatmentNeedles: [String: String]
    var materialNeedles: [String: String]
    var orientationNeedles: Set<String>

    static let `default` = FileRoutingSemanticRules(
        treatmentNeedles: [
            "HF": "HF",
            "B": "baked",
            "BAKE": "baked",
            "BAKED": "baked",
            "ORIGIN": "o",
            "ORIGINAL": "o",
            " O ": "o"
        ],
        materialNeedles: [
            "STO": "STO",
            "NGO": "NGO",
            "MAO": "MAO",
            "MGO": "MGO",
            "AL2O3": "AL2O3",
            "SI": "SI",
            "ONSI": "SI"
        ],
        orientationNeedles: ["111", "110", "001", "100", "0001"]
    )

    static func load(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) -> FileRoutingSemanticRules {
        var rules = FileRoutingSemanticRules.default
        let ruleSet = ruleProvider.ruleSet()

        for entry in ruleSet.substrateTagRules {
            let normalizedValue = normalizeToken(entry.value)
            guard !normalizedValue.isEmpty else {
                continue
            }
            let probes = probesForMatch(entry.match)
            if let treatment = SampleSemanticDescriptor.normalizedProcessingTokenForRules(entry.value) {
                for probe in probes where !probe.isEmpty {
                    rules.treatmentNeedles[probe] = treatment
                }
                continue
            }

            if let material = canonicalMaterial(from: normalizedValue) {
                for probe in probes where !probe.isEmpty {
                    rules.materialNeedles[probe] = material
                }
            }

            if isOrientationToken(normalizedValue) {
                rules.orientationNeedles.insert(normalizedValue)
                for probe in probes where !probe.isEmpty {
                    if isOrientationToken(probe) {
                        rules.orientationNeedles.insert(probe)
                    }
                }
            }
        }

        return rules
    }

    private static func probesForMatch(_ match: FilenameRuleSet.MatchSpec) -> [String] {
        let rawValues = (match.values ?? []) + [match.value].compactMap { $0 }
        return rawValues.map(normalizeToken)
    }

    private static func normalizeToken(_ token: String) -> String {
        token.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    private static func canonicalMaterial(from normalized: String) -> String? {
        if normalized.contains("STO") { return "STO" }
        if normalized.contains("NGO") { return "NGO" }
        if normalized.contains("MAO") { return "MAO" }
        if normalized.contains("MGO") { return "MGO" }
        if normalized.contains("AL2O3") { return "AL2O3" }
        if normalized == "SI" || normalized.contains("ONSI") { return "SI" }
        return nil
    }

    private static func isOrientationToken(_ normalized: String) -> Bool {
        ["111", "110", "001", "100", "0001"].contains(normalized)
    }
}
