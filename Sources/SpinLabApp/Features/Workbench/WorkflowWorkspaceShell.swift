import SwiftUI

/// 通用两列工作区容器。
///
/// 配合 app 侧边栏共同构成整体三列布局：侧边栏 | 左列 | 右列。
/// Shell 负责所有三个 workflow 共享的 UI 区块（操作栏、结果头、状态、图表、trace、warning）。
/// Workflow 专属内容通过 ViewBuilder slot 注入。
///
/// 泛型参数说明：
/// - `Store`: conform `WorkbenchWorkspaceProviding` 的 workflow store
/// - `SearchExtra`: 搜索区扩展（例如 3ω 的 RT 搜索框）
/// - `PlotControls`: Plot 控件区（每个 workflow 自行构建，因 Tab 泛型不同）
/// - `LeftExtra`: 左栏底部扩展（例如 Geometry 面板、Override 面板）
/// - `RightExtra`: 右栏扩展（例如 Scaling 面板）
struct WorkflowWorkspaceShell<
    Store: WorkbenchWorkspaceProviding,
    SearchExtra: View,
    PlotControls: View,
    LeftExtra: View,
    RightExtra: View
>: View {

    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    @ViewBuilder let searchExtra: SearchExtra
    @ViewBuilder let plotControls: PlotControls
    @ViewBuilder let leftExtra: LeftExtra
    @ViewBuilder let rightExtra: RightExtra

    var body: some View {
        AppColumnShell(columnKey: "workbench", defaults: .workbench, left: {
            WorkflowWorkspaceLeftColumn(
                workflowID: workflowID,
                store: store,
                workbench: workbench,
                searchExtra: searchExtra,
                plotControls: plotControls,
                leftExtra: leftExtra
            )
        }, right: {
            WorkflowWorkspaceRightColumn(
                workflowID: workflowID,
                store: store,
                workbench: workbench,
                rightExtra: rightExtra
            )
        })
    }
}
