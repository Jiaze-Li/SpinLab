import Foundation

/// The runtime object a format loader produces from one raw measurement file, per the
/// 2026-08-08 MeasurementData/Signal architecture audit §6. Named `LoadedMeasurement`, not
/// `MeasurementData` — that name is already in use by
/// `WorkbenchMeasurementDataStore`/`WorkbenchMetricRecord` (Workbench/Modules/PlotSystem/
/// Contracts/WorkbenchResultContracts.swift), a persisted scalar analysis-metric store. Reusing
/// "MeasurementData" for this raw-loaded-signal type would collide, in name, with that unrelated,
/// already-shipping type at the opposite end of the pipeline.
///
/// Never persisted verbatim: every workflow keeps its own interpreted/derived result type
/// (e.g. `IVSweep`) for that purpose. `LoadedMeasurement` exists only to cross the
/// loader -> workflow boundary in memory.
///
/// No `hints` field: the audit (§7) found the existing filename-hint type
/// (`SpinLabDomain.ParsedFilenameHints`, resolved via Sidecar) already owns filename-derived
/// experimental conditions, and recommended loaders stop re-deriving them independently rather
/// than growing a second, competing hints type. IV's vertical slice has no loader-owned filename
/// evidence that isn't already covered by that path (temperature-from-stem stays IV workflow
/// interpretation, unchanged, in `IVLVMParser`), so no hints field is introduced here. Add one
/// only when a later migration finds a genuine, loader-owned need (see report for Phase 3c).
struct LoadedMeasurement: Sendable {
    let sourceFilePath: String
    let format: MeasurementFileFormat
    var signals: [MeasurementColumn]
    let rowCount: Int
    let diagnostics: [MeasurementDiagnostic]

    init(sourceFilePath: String,
         format: MeasurementFileFormat,
         signals: [MeasurementColumn],
         rowCount: Int,
         diagnostics: [MeasurementDiagnostic] = []) {
        self.sourceFilePath = sourceFilePath
        self.format = format
        self.signals = signals
        self.rowCount = rowCount
        self.diagnostics = diagnostics
    }
}
