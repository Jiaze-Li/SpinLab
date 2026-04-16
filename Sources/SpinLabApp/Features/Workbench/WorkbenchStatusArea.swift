import SwiftUI

// MARK: - WorkbenchStatusArea

/// 通用状态消息区。
/// 三条消息各自独立，非空才显示，全空时整个 view 不占空间。
///
/// ## 自定义提示
/// - 字号、颜色、消息合并方式可按需修改
struct WorkbenchStatusArea: View {
    let searchMessage: String?
    let plotMessage: String?
    let loadMessage: String?

    // TODO(用户设计): 考虑是否合并为单条消息、是否加图标前缀
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let msg = searchMessage, !msg.isEmpty {
                Text(msg).font(.callout).foregroundStyle(.secondary)
            }
            if let msg = plotMessage, !msg.isEmpty {
                Text(msg).font(.callout).foregroundStyle(.secondary)
            }
            if let msg = loadMessage, !msg.isEmpty {
                Text(msg).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
