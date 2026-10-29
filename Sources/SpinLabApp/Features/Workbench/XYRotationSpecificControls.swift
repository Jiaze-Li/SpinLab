import SwiftUI

// MARK: - XY Rotation-specific controls
//
// Specific content for the shared Controls Surface (spec 06 §5): Data Correction (Center,
// Detrend) · Plot Annotation (x=180) · Per-file Calibration (φ offset per file). The leaf below
// takes plain values and a closure; `XYRotationWorkspaceStore.controlsSpecificContent` reads the
// store (CS-28).

struct XYRotationPhiOffsetRow: Identifiable, Equatable {
    let id: String
    let stem: String
    let offset: Double
}

/// Per-file φ offset editor. A file list with one numeric field per file is a compound input,
/// so it arranges its own rows internally; the Surface decides where it sits and how wide it is.
struct XYRotationPhiOffsetInput: WorkbenchLeafInput {
    let rows: [XYRotationPhiOffsetRow]
    let onOffsetChange: (_ sweepID: String, _ offset: Double) -> Void

    var body: some View {
        if rows.isEmpty {
            Text("Run analysis to see per-file offsets.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(rows) { row in
                    HStack(spacing: AppSpacing.sm) {
                        Text(row.stem)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        TextField(
                            "0",
                            value: Binding(get: { row.offset }, set: { onOffsetChange(row.id, $0) }),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: WorkbenchInputWidth.compact)
                        .monospacedDigit()
                    }
                }
            }
        }
    }
}

extension XYRotationWorkspaceStore {
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        standardControlsDescriptor(
            appState: appState,
            globalPlotDefaults: globalPlotDefaults,
            flushSource: "xyRotationStyleChange",
            canReorderSeries: canReorderSeries,
            currentSeriesOrder: activeSeriesOrder,
            rendererTitleTokens: ["tab", "device"],
            specific: controlsSpecificContent(appState: appState)
        )
    }

    @MainActor
    func controlsSpecificContent(appState: SpinLabAppState) -> WorkbenchSpecificContent {
        let rows: [XYRotationPhiOffsetRow] = (ingestionResult?.sweeps ?? []).map { sweep in
            XYRotationPhiOffsetRow(
                id: sweep.id, stem: sweep.stem,
                offset: phiOffsetOverrides[sweep.id] ?? sweep.defaultPhiOffset)
        }
        func flushed(_ source: String?) -> () -> Void {
            {
                self.rerenderForStyleChange()
                if let source { appState.scheduleInteractionSnapshotFlush(source: source) }
            }
        }
        let centerChanged = flushed("xyRotationCenterBaselineChange")
        let detrendChanged = flushed("xyRotationLinearDetrendChange")
        let annotationChanged = flushed(nil)
        return WorkbenchSpecificContent {
            WorkbenchSpecificGroup("dataCorrection", title: "Data Correction") {
                WorkbenchSpecificRow("corrections") {
                    WorkbenchSpecificInput.toggle("center", title: "Center", isOn: Binding(
                        get: { self.centerBaseline },
                        set: { self.centerBaseline = $0; centerChanged() }))
                    WorkbenchSpecificInput.toggle("detrend", title: "Detrend", isOn: Binding(
                        get: { self.linearDetrend },
                        set: { self.linearDetrend = $0; detrendChanged() }))
                }
            }
            WorkbenchSpecificGroup("plotAnnotation", title: "Plot Annotation") {
                WorkbenchSpecificRow("annotation") {
                    WorkbenchSpecificInput.toggle("line180", title: "x=180", isOn: Binding(
                        get: { self.showAuxiliaryLine180 },
                        set: { self.showAuxiliaryLine180 = $0; annotationChanged() }))
                }
            }
            WorkbenchSpecificGroup("calibration", title: "Per-file Calibration (φ offset, deg)") {
                WorkbenchSpecificRow("phiOffset", label: "φ offset (deg)") {
                    WorkbenchSpecificInput.control("offsets", fills: true, XYRotationPhiOffsetInput(
                        rows: rows,
                        onOffsetChange: { sweepID, offset in
                            self.updatePhiOffset(sweepID: sweepID, offset: offset)
                            appState.scheduleInteractionSnapshotFlush(source: "xyRotationPhiOffsetChange")
                        }))
                }
            }
        }
    }
}
