import SwiftUI

/// 通用两列工作区容器。
///
/// 配合 app 侧边栏共同构成整体三列布局：侧边栏 | 左列 | 右列。
/// 每列内容由调用方通过 `@ViewBuilder` 注入。
/// 内部转发到 `AppColumnShell`，列宽通过 `@AppStorage` 持久化。
struct WorkflowWorkspaceShell<Left: View, Right: View>: View {

    @ViewBuilder let leftColumn: () -> Left
    @ViewBuilder let rightColumn: () -> Right

    var body: some View {
        AppColumnShell(columnKey: "workbench", defaults: .workbench,
                       left: leftColumn, right: rightColumn)
    }
}
