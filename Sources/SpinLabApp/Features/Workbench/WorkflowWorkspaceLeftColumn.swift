import SwiftUI

struct WorkflowWorkspaceLeftColumn<
    Store: WorkbenchWorkspaceProviding,
    SearchExtra: View,
    PlotControls: View,
    LeftExtra: View
>: View {

    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    let searchExtra: SearchExtra
    let plotControls: PlotControls
    let leftExtra: LeftExtra

    @AppStorage("workbench.selectedHitsTrayWidth") private var trayWidth: Double = 250
    @State private var trayWidthBase: Double = 250

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                titleBar
                WorkflowWorkspaceSearchSection(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench,
                    searchExtra: searchExtra
                )
                plotControls
                leftExtra
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                WorkflowWorkspaceResultsList(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if workbench.selectedCount(for: workflowID) > 0 {
                    trayDivider
                    SelectedHitsTray(workflowID: workflowID, workbench: workbench)
                        .frame(minWidth: CGFloat(trayWidth), maxWidth: CGFloat(trayWidth), maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { trayWidthBase = trayWidth }
    }

    private var trayDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: 8)             // wider drag target
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = trayWidthBase - value.translation.width
                        trayWidth = proposed.clamped(to: 220...380)
                    }
                    .onEnded { value in
                        let proposed = trayWidthBase - value.translation.width
                        trayWidth = proposed.clamped(to: 220...380)
                        trayWidthBase = trayWidth
                    }
            )
    }

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(workbench.selectedWorkflowDefinition?.displayName ?? "Workflow")
                .font(AppFontScale.sectionTitle)
            Spacer()
        }
        .padding(.top, AppSpacing.xs)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
