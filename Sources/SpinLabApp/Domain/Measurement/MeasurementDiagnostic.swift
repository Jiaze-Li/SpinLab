import Foundation

/// A structured fact a format loader observed while reading a file — e.g. a skipped malformed
/// row, or a column the loader expected but did not find. Replaces the free-text `[String]`
/// warning arrays every loader accumulated before Phase 3c; the *existence* of a diagnostic is
/// always a fact, even when its cause (a malformed row, an unreadable value) is interpretive.
///
/// Per the 2026-08-08 architecture audit §6, this lives on `LoadedMeasurement`, not on any
/// workflow result type — workflows translate diagnostics into their own warning presentation at
/// the ingestion boundary rather than reading this type directly in UI code.
struct MeasurementDiagnostic: Hashable, Sendable {
    let code: String
    let message: String
    let columnKey: String?
    let rowIndex: Int?

    init(code: String, message: String, columnKey: String? = nil, rowIndex: Int? = nil) {
        self.code = code
        self.message = message
        self.columnKey = columnKey
        self.rowIndex = rowIndex
    }
}

extension MeasurementDiagnostic {
    /// Presents this diagnostic as a workflow-facing warning string (Phase 4a: the minimum wiring
    /// needed to surface loader-observed facts — e.g. a padded/truncated malformed row — through
    /// the existing `warnings: [String]` outputs AHE/RT/XY-Rotation-DAT already have, instead of
    /// discarding them). `message` is already human-readable; this only adds file context.
    func asWorkflowWarning(fileName: String) -> String {
        "\(fileName): \(message)"
    }
}
