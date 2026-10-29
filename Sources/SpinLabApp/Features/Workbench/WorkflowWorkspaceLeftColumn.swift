import SwiftUI

/// The workflow workspace's left column: title, search/action bar, the shared Controls Surface
/// and the results list. Controls are mounted only through `WorkbenchControlsSurface`; a
/// workflow supplies a descriptor and cannot place Common/Plot/Specific itself (spec 06 CS-1).
struct WorkflowWorkspaceLeftColumn<
    Store: WorkbenchWorkspaceProviding,
    SearchExtra: View,
    LeftExtra: View,
    ActionBarTrailing: View
>: View {

    let workflowID: String
    let store: Store
    let workbench: WorkbenchFeatureStore

    let searchExtra: SearchExtra
    let surface: WorkbenchControlsSurface
    let leftExtra: LeftExtra
    let actionBarTrailing: ActionBarTrailing

    init(
        workflowID: String,
        store: Store,
        workbench: WorkbenchFeatureStore,
        controls: WorkbenchControlsDescriptor,
        @ViewBuilder searchExtra: () -> SearchExtra,
        @ViewBuilder leftExtra: () -> LeftExtra,
        @ViewBuilder actionBarTrailing: () -> ActionBarTrailing
    ) {
        self.workflowID = workflowID
        self.store = store
        self.workbench = workbench
        self.searchExtra = searchExtra()
        self.surface = WorkbenchControlsSurface(descriptor: controls)
        self.leftExtra = leftExtra()
        self.actionBarTrailing = actionBarTrailing()
    }

    var body: some View {
        GeometryReader { column in
            content(controlsMaxHeight: max(column.size.height * Self.controlsHeightFraction, Self.controlsMinCap))
        }
    }

    /// Share of the column the controls may occupy before they scroll (CS-26): the results
    /// list below always keeps the rest and stays reachable however many groups Specific adds.
    private static var controlsHeightFraction: CGFloat { 0.55 }
    private static var controlsMinCap: CGFloat { 240 }

    private func content(controlsMaxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                titleBar
                WorkflowWorkspaceSearchSection(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench,
                    searchExtra: searchExtra,
                    actionBarTrailing: actionBarTrailing
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)

            ControlsScrollRegion(maxHeight: controlsMaxHeight) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    surface
                    leftExtra
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
            }

            Divider()

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    WorkflowWorkspaceResultsList(
                        workflowID: workflowID,
                        store: store,
                        workbench: workbench
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Single-selection workflows (AFM, RSM) hold at most one file, which the results list
                    // already shows; the Selected tray is only useful when several can accumulate.
                    if workbench.selectionMode(for: workflowID) == .multiple,
                       workbench.basketSelectedCount(for: workflowID) > 0 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: SelectedHitsLayout.separatorWidth)

                        SelectedHitsTray(workflowID: workflowID, workbench: workbench)
                            .frame(width: SelectedHitsLayout.width(primaryWidth: proxy.size.width))
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

/// Sizes to its content up to `maxHeight`, then scrolls vertically. Keeps the results list
/// reachable when the Controls Surface grows (spec 06 CS-26).
private struct ControlsScrollRegion<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
    }
}
