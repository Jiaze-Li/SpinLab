import SwiftUI

// MARK: - SegmentedControlRow

/// Shared label + segmented picker row.
struct SegmentedControlRow<Selection: Hashable, Content: View>: View {
    let label: String
    var labelWidth: CGFloat? = nil
    @Binding var selection: Selection
    var pickerMaxWidth: CGFloat? = nil
    var onSelectionChange: ((Selection) -> Void)? = nil
    @ViewBuilder let options: () -> Content

    var body: some View {
        ControlRow(label: label, labelWidth: labelWidth) {
            Picker("", selection: binding) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: pickerMaxWidth)
        }
    }

    private var binding: Binding<Selection> {
        Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                onSelectionChange?(newValue)
            }
        )
    }
}
