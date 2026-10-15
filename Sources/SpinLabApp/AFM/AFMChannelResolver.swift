import Foundation

/// Default active-channel resolution policy (Phase 2C). Workflow-owned — Heatmap never sees
/// this. See `docs/architecture/workbench/datasets/AFMDatasetContract.md`.
enum AFMChannelResolver {
    struct Resolution {
        let channel: CanonicalAFMChannel?
        let warning: String?
    }

    /// 1. First channel whose semantic type case-insensitively equals "Height".
    /// 2. Otherwise, first channel whose source label contains "height" (case-insensitive).
    /// 3. Otherwise, the first channel, with a warning that no Height channel was identified.
    /// 4. No channels at all: no default, warning only.
    static func resolveDefaultChannel(in channels: [CanonicalAFMChannel]) -> Resolution {
        if let byType = channels.first(where: { $0.isSemanticHeight }) {
            return Resolution(channel: byType, warning: nil)
        }
        if let byLabel = channels.first(where: { $0.sourceLabel.lowercased().contains("height") }) {
            return Resolution(channel: byLabel, warning: nil)
        }
        if let first = channels.first {
            return Resolution(
                channel: first,
                warning: "No Height channel identified; defaulting to \"\(first.sourceLabel)\"."
            )
        }
        return Resolution(channel: nil, warning: "AFM dataset has no channels.")
    }
}
