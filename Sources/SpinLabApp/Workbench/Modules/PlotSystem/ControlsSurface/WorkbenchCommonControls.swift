import SwiftUI

/// Everything Common needs, as plain values and closures (CS-10). It knows nothing about
/// plot modes, workflows or stores. Closures carry the adapter's re-render / flush policy.
struct WorkbenchCommonControlsModel {
    var showTitle: Bool
    var titleOverride: String
    var renderedTitle: String
    var sourceResetToken: String
    var globalPlotDefaults: Binding<[String: String]>
    var onShowTitleChange: (Bool) -> Void
    var onTitleOverride: (String) -> Void
    /// Title size / transparent background (shared plot defaults) changed.
    var onStyleChange: () -> Void
}

/// Show Title · Plot title · Title Size · Transparent — the same four groups, in this order,
/// for every workflow (CS-8).
struct WorkbenchCommonControls: View {
    let model: WorkbenchCommonControlsModel

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: model.globalPlotDefaults.wrappedValue)
        WorkbenchControlFlow {
            WorkbenchControlGroup(id: "controls.common.showTitle") {
                Toggle("Show Title", isOn: Binding(get: { model.showTitle }, set: { model.onShowTitleChange($0) }))
                    .toggleStyle(.checkbox)
            }
            .workbenchFlowFill(false)

            WorkbenchControlGroup(id: "controls.common.plotTitle") {
                WorkbenchControlRow(id: "controls.common.plotTitle.field", label: "Plot title") {
                    LabelOverrideField(
                        label: "",
                        renderedDefault: model.renderedTitle,
                        currentValue: model.titleOverride,
                        sourceResetToken: model.sourceResetToken,
                        onCommit: model.onTitleOverride,
                        fieldMaxWidth: .infinity
                    )
                }
            }
            .workbenchFlowFill()

            WorkbenchControlGroup(id: "controls.common.titleSize") {
                WorkbenchControlRow(id: "controls.common.titleSize.picker", label: "Title size") {
                    SharedPlotFontSizePicker(
                        label: "",
                        current: style.titleFontSize,
                        rawValue: model.globalPlotDefaults.valueBinding(forKey: "titleFontSize"),
                        onStyleChange: model.onStyleChange
                    )
                }
            }

            WorkbenchControlGroup(id: "controls.common.transparent") {
                SharedPlotTransparentBackgroundToggle(
                    globalPlotDefaults: model.globalPlotDefaults,
                    onStyleChange: model.onStyleChange
                )
            }
        }
    }
}
