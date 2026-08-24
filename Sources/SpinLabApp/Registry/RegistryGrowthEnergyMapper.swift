import Foundation

/// Canonical Registry-facing interpretation and formatting for the "能量"
/// (laser energy) column — Phase 5.4.4 reconciliation. Audited against the
/// real production Registry (`实验记录.xlsx`, LNO/NNO/NCO/PLD-N样品 sheets)
/// and the real Obsidian vault (`03 Experiments`) rather than invented: the
/// domain has THREE distinct named components, never a single magnitude.
///
/// Real Registry forms observed (canonical write-facing convention):
///   "镜前100mJ，激光238 mJ (24kV)"   — full triple
///   "镜前45mJ，激光90 (20.1kV)"       — laser number without its own "mJ"
///   "160mJ"                           — bare primary only (legacy, no
///                                        separate laser/output reading yet)
///   "110mJ (20.2kV)"                  — bare primary + voltage, no laser
///   "衰减镜220mJ (25.1kV)"            — attenuator reading stands in for
///                                        the primary/pre-optics component
///   "镜前48mJ，衰减镜，激光197 mJ (21.8kV)" — a bare "衰减镜" flag (no
///                                        number of its own) between primary
///                                        and laser: attenuator was in the
///                                        beam path, not a fourth component
/// Real Obsidian form (`energy:` frontmatter, always the full positional
/// triple or empty — never partial):
///   "110 mJ 26.3 kV 280 mJ"           — primary, voltage, laser, in order
///   "衰减镜 53 mJ 23.7 kV 247 mJ"     — same triple, attenuator-labeled
enum RegistryGrowthEnergyMapper {
    /// The three named semantic components. `primary` is the mirror-front
    /// (镜前) or attenuator (衰减镜) pre-optics energy; `voltage` is the
    /// laser high-voltage setting; `output` is the downstream/laser (激光)
    /// measured energy. Each is independently optional — compatibility is
    /// evaluated per-component, never as one combined magnitude.
    struct EnergyComponents: Equatable, Sendable {
        var primary: Double?
        var voltage: Double?
        var output: Double?

        var isEmpty: Bool { primary == nil && voltage == nil && output == nil }
    }

    /// Parses the Obsidian `energy:` claim — always the strict positional
    /// triple "<primary> mJ <voltage> kV <output> mJ", optionally prefixed
    /// with a "衰减镜" label (never affects position/meaning). Returns nil
    /// for anything else — Obsidian energy claims are never partial in the
    /// audited vault, so a non-matching shape is unparseable, not a
    /// different valid shape to guess at.
    static func parseObsidian(_ raw: String) -> EnergyComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"^(?:衰减镜\s*)?([\d.]+)\s*mJ\s+([\d.]+)\s*kV\s+([\d.]+)\s*mJ$"#
        guard let match = firstMatch(pattern: pattern, in: trimmed),
              let primary = Double(match.group(1)),
              let voltage = Double(match.group(2)),
              let output = Double(match.group(3)) else { return nil }
        return EnergyComponents(primary: primary, voltage: voltage, output: output)
    }

    /// Parses a Registry "能量" cell into its named components. Consumes
    /// each recognized token (voltage in parens, "激光..." output, a leading
    /// "镜前"/"衰减镜"-labeled or bare primary) out of a working copy of the
    /// string; if any numeric literal remains unconsumed afterward (e.g. the
    /// rare "衰减镜220mJ (25.1kV) 镜前57mJ" shape, which names two
    /// independent numbers with no way to safely tell which role either
    /// plays), parsing fails closed — nil, never a guess. Decorative
    /// trailing remarks with no digits (e.g. "，无衰减，", "，能量不稳定")
    /// are harmless leftover text and do not fail parsing.
    static func parseRegistry(_ raw: String) -> EnergyComponents? {
        var remaining = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return nil }

        var voltage: Double?
        if let match = firstMatch(pattern: #"\(\s*([\d.]+)\s*kV\s*\)"#, in: remaining) {
            voltage = Double(match.group(1))
            remaining.removeSubrange(match.range)
        }

        var output: Double?
        if let match = firstMatch(pattern: #"激光\s*([\d.]+)\s*(?:mJ)?"#, in: remaining) {
            output = Double(match.group(1))
            remaining.removeSubrange(match.range)
        }

        var primary: Double?
        if let match = firstMatch(pattern: #"^\s*(?:镜前|衰减镜)?\s*([\d.]+)\s*mJ"#, in: remaining) {
            primary = Double(match.group(1))
            remaining.removeSubrange(match.range)
        }

        guard primary != nil || voltage != nil || output != nil else { return nil }
        // Fail closed on any stray digit left in the remainder — a second,
        // unattributed number this parser has no safe role to assign it to.
        guard remaining.range(of: #"\d"#, options: .regularExpression) == nil else { return nil }

        return EnergyComponents(primary: primary, voltage: voltage, output: output)
    }

    /// The canonical Registry write-facing string for a (possibly merged)
    /// `EnergyComponents` — the ONE representation used for Ready/enrichment
    /// preview and the actual candidate workbook write, mirroring the real
    /// "镜前100mJ，激光238 mJ (24kV)" convention.
    static func registryDisplayString(_ components: EnergyComponents) -> String {
        var parts: [String] = []
        if let primary = components.primary {
            parts.append(components.output != nil ? "镜前\(formatNumber(primary))mJ" : "\(formatNumber(primary))mJ")
        }
        if let output = components.output {
            parts.append("激光\(formatNumber(output))mJ")
        }
        var result = parts.joined(separator: "，")
        if let voltage = components.voltage {
            let voltageText = "\(formatNumber(voltage))kV"
            result = result.isEmpty ? voltageText : "\(result) (\(voltageText))"
        }
        return result
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private struct RegexMatch {
        let range: Range<String.Index>
        let groups: [String]
        func group(_ index: Int) -> String { groups[index - 1] }
    }

    private static func firstMatch(pattern: String, in string: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let result = regex.firstMatch(in: string, options: [], range: nsRange),
              let fullRange = Range(result.range, in: string) else { return nil }
        var groups: [String] = []
        for i in 1..<result.numberOfRanges {
            guard let groupRange = Range(result.range(at: i), in: string) else { return nil }
            groups.append(String(string[groupRange]))
        }
        return RegexMatch(range: fullRange, groups: groups)
    }
}
