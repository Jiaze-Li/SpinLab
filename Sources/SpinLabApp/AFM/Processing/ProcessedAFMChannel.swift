import Foundation

/// Output of `AFMProcessingPipeline` — a derived channel matrix, built fresh from the immutable
/// `CanonicalAFMChannel` on every reprocess. Never written back into `CanonicalAFMDataset`.
struct ProcessedAFMChannel: Sendable, Equatable {
    let sourceChannelID: String
    /// `values[y][x]`, same dimensions as the source channel.
    let values: [[Double]]
    let canonicalUnit: String
    let displayLabel: String
    let configuration: AFMProcessingConfiguration
    /// Warnings raised while processing (e.g. insufficient finite points for a fit). Coalesced —
    /// not one entry per affected row/pixel.
    let warnings: [String]
}
