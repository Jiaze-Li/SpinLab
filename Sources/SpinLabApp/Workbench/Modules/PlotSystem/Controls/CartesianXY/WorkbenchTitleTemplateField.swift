import SwiftUI

// MARK: - WorkbenchTitleTemplateField

/// Shared title template input field (label + text box only).
/// Used by 3ω, AHE, and DualAxis plot controls.
struct WorkbenchTitleTemplateField: View {
    @Binding var titleTemplate: String
    var onChange: (() -> Void)? = nil

    var body: some View {
        SharedPlotTextFieldRow(
            label: "Title template",
            placeholder: "#tab #device #sample",
            text: $titleTemplate,
            fieldMinWidth: nil,
            onTextChange: onChange
        )
    }
}

// MARK: - WorkbenchAvailableTokensHint

/// Shared "Available: #tab #method ..." hint, decoupled from the input row so it can span
/// the full width of its containing panel instead of being constrained by the input row's
/// trailing controls.
struct WorkbenchAvailableTokensHint: View {
    let numericDisplayCache: [String: [String: String]]

    var body: some View {
        Text(hint)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String {
        var tokens = ["#tab", "#method", "#device", "#sample"]
        let numericKeys = numericDisplayCache.values.flatMap { $0.keys }
        for key in Set(numericKeys).sorted() {
            tokens.append("#\(key)")
        }
        return "Available: " + tokens.joined(separator: " ")
    }
}

// MARK: - WorkbenchTitleTemplateSection

/// Shared two-row title template layout:
///   Row 1: Title template input + workflow-specific trailing controls (e.g. Point Tags,
///          stack offset slider, Gap input).
///   Row 2: Available-tokens hint, spanning the full panel width so it can extend past the
///          input row's right edge instead of wrapping early.
///
/// This is the layout every workflow using `WorkbenchStandardPlotControls` or
/// `DualAxisPlotControlsPanel` should go through so the hint's available width is never
/// clipped by the input row above it.
struct WorkbenchTitleTemplateSection<Trailing: View>: View {
    @Binding var titleTemplate: String
    let numericDisplayCache: [String: [String: String]]
    var onChange: (() -> Void)? = nil
    @ViewBuilder var trailingContent: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 12) {
                WorkbenchTitleTemplateField(
                    titleTemplate: $titleTemplate,
                    onChange: onChange
                )
                trailingContent()
            }
            WorkbenchAvailableTokensHint(numericDisplayCache: numericDisplayCache)
        }
    }
}
