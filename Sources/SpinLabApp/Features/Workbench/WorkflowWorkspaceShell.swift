import SwiftUI

/// 通用两列工作区容器。
///
/// 配合 app 侧边栏共同构成整体三列布局：侧边栏 | 左列 | 右列。
/// 每列内容由调用方通过 `@ViewBuilder` 注入，shell 只负责列划分和宽度。
///
/// ## 列分工
/// - `leftColumn`   操作区（搜索输入、结果列表、参数控件）
/// - `rightColumn`  展示区（图像输出、trace、消息）
///
/// ## 列宽调整
/// 修改 `frame(minWidth:idealWidth:maxWidth:)` 参数即可调整宽度范围。
struct WorkflowWorkspaceShell<Left: View, Right: View>: View {

    @ViewBuilder let leftColumn: () -> Left
    @ViewBuilder let rightColumn: () -> Right

    var body: some View {
        HSplitView {

            // ── 左列：操作区（镜像 Library 左列宽度）────────────────────────────
            leftColumn()
                .frame(minWidth: 360, idealWidth: 480, maxWidth: 640)
                .layoutPriority(1)

            // ── 右列：展示区（镜像 Library 右列宽度）────────────────────────────
            rightColumn()
                .frame(minWidth: 320, idealWidth: 500, maxWidth: .infinity)
                .layoutPriority(0)
        }
    }
}
