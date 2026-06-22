import SwiftUI

/// RSM workflow-specific view selector for the heatmap control surface.
struct RSMViewSelector: View {
    @Binding var activeView: RSMView
    let parsedDataset: CanonicalRSMDataset?
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("View")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            Picker("", selection: $activeView) {
                ForEach(RSMView.allCases, id: \.self) { view in
                    Text(view.rawValue.uppercased()).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: activeView) { _, _ in
                onChange()
            }
            if let dataset = parsedDataset, !dataset.isViewCompatible(activeView) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This view is not valid for the loaded data. Recommended: \(dataset.recommendedView.rawValue.uppercased())")
            }
        }
    }
}
