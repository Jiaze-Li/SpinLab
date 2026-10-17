import SwiftUI

/// Everything Common needs, as plain values and closures (CS-10). It knows nothing about
/// plot modes, workflows or stores. Closures carry the adapter's re-render / flush policy.
struct WorkbenchCommonControlsModel {
    var showTitle: Bool
    var titleOverride: String
    /// Placeholder of the Plot title field: the title that renders when no override is set
    /// (template result, else the source default; CS-9a).
    var renderedTitle: String
    var sourceResetToken: String
    var globalPlotDefaults: Binding<[String: String]>
    /// Title template text (one syntax and one resolver for every Plot Mode; CS-9).
    var titleTemplate: Binding<String>
    /// Template tokens the active data actually supports, each with its leading `#`.
    var availableTokens: [String]
    var onShowTitleChange: (Bool) -> Void
    var onTitleOverride: (String) -> Void
    /// The template text changed.
    var onTitleTemplateChange: () -> Void
    /// Transparent background (shared plot defaults) changed.
    var onStyleChange: () -> Void
}

/// Plot title · Show Title · Transparent · Title template (+Available) — the same controls, in
/// this order, for every workflow and Plot Mode (CS-8).
struct WorkbenchCommonControls: View {
    let model: WorkbenchCommonControlsModel

    var body: some View {
        WorkbenchControlFlow {
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

            WorkbenchControlGroup(id: "controls.common.showTitle") {
                WorkbenchCheckbox(
                    title: "Show Title",
                    isOn: Binding(get: { model.showTitle }, set: { model.onShowTitleChange($0) }),
                    id: "controls.common.showTitle.checkbox")
            }
            .workbenchFlowFill(false)

            WorkbenchControlGroup(id: "controls.common.transparent") {
                SharedPlotTransparentBackgroundToggle(
                    globalPlotDefaults: model.globalPlotDefaults,
                    onStyleChange: model.onStyleChange,
                    roleID: "controls.common.transparent.checkbox"
                )
            }

            WorkbenchControlGroup(id: "controls.common.titleTemplate") {
                WorkbenchControlRow(id: "controls.common.titleTemplate.field", label: "Title template") {
                    SharedPlotTextFieldRow(
                        label: "",
                        placeholder: "#tab #device #sample",
                        text: model.titleTemplate,
                        fieldMinWidth: WorkbenchInputWidth.compact,
                        fieldIdealWidth: WorkbenchInputWidth.wide,
                        fieldMaxWidth: .infinity,
                        onTextChange: model.onTitleTemplateChange
                    )
                }
                WorkbenchAvailableTokensHint(tokens: model.availableTokens)
            }
            .workbenchFlowFill()
        }
    }
}
