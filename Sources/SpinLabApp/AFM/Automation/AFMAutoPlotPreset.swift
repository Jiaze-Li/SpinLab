import Foundation

/// How the automatic AFM plot picks its single channel. Explicit and strict: zero or several matches
/// mean "skip and say why" — never a fallback to another channel (Task 7 design §2.3-4).
struct AFMAutoChannelRule: Codable, Equatable, Hashable, Sendable {
    /// Case-insensitive match on the channel's semantic type (e.g. "Height"). Nil = not constrained.
    var semanticType: String?
    /// Case-insensitive exact match on the channel's source label (e.g. "HeightRetrace"). Nil = not constrained.
    var sourceLabel: String?

    var isUsable: Bool {
        (semanticType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            || (sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    func summary() -> String {
        [semanticType.map { "type \($0)" }, sourceLabel.map { "label \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Pure channel selection for headless callers. Lives in the AFM layer, has no UI state.
enum AFMAutoChannelSelector {
    enum Outcome: Equatable {
        case selected(channelID: String)
        case ruleNotUsable
        case noMatch
        case ambiguous(count: Int)

        var skipReason: String? {
            switch self {
            case .selected: return nil
            case .ruleNotUsable: return "The preset has no usable channel rule."
            case .noMatch: return "No channel matches the preset's channel rule."
            case let .ambiguous(count): return "\(count) channels match the preset's channel rule; it must pick exactly one."
            }
        }
    }

    static func select(rule: AFMAutoChannelRule, in channels: [CanonicalAFMChannel]) -> Outcome {
        guard rule.isUsable else { return .ruleNotUsable }
        func norm(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed.lowercased()
        }
        let type = norm(rule.semanticType)
        let label = norm(rule.sourceLabel)
        let matches = channels.filter { channel in
            if let type, channel.semanticTypeRaw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != type { return false }
            if let label, channel.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != label { return false }
            return true
        }
        switch matches.count {
        case 0: return .noMatch
        case 1: return .selected(channelID: matches[0].id)
        default: return .ambiguous(count: matches.count)
        }
    }
}

/// The one Library-level automation preset: enablement plus the *actual* science and display values.
/// `presetVersionID` is a random UUID regenerated on every Apply or enabled change; it is the only
/// configuration identity (Task 7 design §2.4). Nothing here is a hard-coded research default.
struct AFMAutoPlotPreset: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var enabled: Bool
    var presetVersionID: String
    var channelRule: AFMAutoChannelRule
    var surfaceLevel: AFMSurfaceLevel
    var lineFlattenOrder: AFMLineFlattenOrder
    var zeroReference: AFMZeroReference
    var displayState: HeatmapTabRenderState
    var scaleBar: AFMScaleBarSetting
    /// Global plot style values frozen at Apply time, so a later change of global defaults cannot make
    /// an automatic figure irreproducible.
    var globalPlotDefaults: [String: String]

    static func newVersionID() -> String { UUID().uuidString.lowercased() }

    func processingConfiguration(channelID: String) -> AFMProcessingConfiguration {
        AFMProcessingConfiguration(
            activeChannelID: channelID, surfaceLevel: surfaceLevel, lineFlattenOrder: lineFlattenOrder,
            zeroReference: zeroReference
        )
    }
}

enum AFMAutoPlotPresetLoad: Equatable, Sendable {
    /// No preset file: automation is off.
    case absent
    case loaded(AFMAutoPlotPreset)
    /// Corrupt or unknown version: treated as off (fail-closed), never repaired.
    case unreadable(String)

    var effective: AFMAutoPlotPreset? {
        if case let .loaded(preset) = self { return preset }
        return nil
    }
}
