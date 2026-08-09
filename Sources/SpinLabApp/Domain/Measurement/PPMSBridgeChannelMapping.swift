import Foundation

/// Shared ch1/ch2/ch3 -> PPMS bridge-index mapping.
///
/// Phase 4a: extracted from two independently-implemented, byte-for-byte-identical switch
/// statements (`RTPPMSDatParser.bridgeIndex(forChannel:)` and `AHEChannel.bridgeIndex`) found by
/// the 2026-08-08 Phase 4 workflow-interpretation audit. RT and AHE both consume this; XY Rotation
/// resolves bridge 2/3 directly by name and has no channel-string input, so it does not use this.
enum PPMSBridgeChannelMapping {
    /// ch1 -> 1, ch2 -> 2, ch3 -> 3 (case-insensitive). Returns nil for unrecognized values.
    static func bridgeIndex(forChannel channel: String) -> Int? {
        switch channel.lowercased() {
        case "ch1": return 1
        case "ch2": return 2
        case "ch3": return 3
        default: return nil
        }
    }
}
