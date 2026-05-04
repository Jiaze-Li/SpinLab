import Foundation

/// Lightweight snapshot of overlay data — decoupled from vault so overlays survive deletion.
struct OverlaySnapshot: Sendable {
    let label: String
    let sweeps: [ThreeOmegaFieldSweepResult]
    let sourceFiles: [String]
    let sampleKeys: [String]
}
