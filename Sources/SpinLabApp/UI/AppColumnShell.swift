import SwiftUI

/// Default column width constraints for each area's two-column layout.
struct ColumnDefaults {
    var leftMin: CGFloat
    var leftIdeal: CGFloat
    var leftMax: CGFloat
    var rightMin: CGFloat

    static let inbox = ColumnDefaults(leftMin: 380, leftIdeal: 500, leftMax: 1200, rightMin: 280)
    static let workbench = ColumnDefaults(leftMin: 360, leftIdeal: 480, leftMax: 640, rightMin: 320)
    static let library = ColumnDefaults(leftMin: 420, leftIdeal: 520, leftMax: 680, rightMin: 320)
}

/// Unified two-column split view with persistent left-column width.
///
/// Replaces per-area HSplitView + hardcoded frame values. The user's chosen
/// divider position is saved to `@AppStorage("splitView.\(columnKey).leftWidth")`
/// and restored on next launch.
struct AppColumnShell<Left: View, Right: View>: View {
    let defaults: ColumnDefaults
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    @AppStorage private var savedLeftWidth: Double

    init(columnKey: String, defaults: ColumnDefaults,
         @ViewBuilder left: @escaping () -> Left,
         @ViewBuilder right: @escaping () -> Right) {
        self.defaults = defaults
        self.left = left
        self.right = right
        _savedLeftWidth = AppStorage(wrappedValue: Double(defaults.leftIdeal),
                                      "splitView.\(columnKey).leftWidth")
    }

    var body: some View {
        let clampedWidth = min(max(CGFloat(savedLeftWidth), defaults.leftMin), defaults.leftMax)
        HSplitView {
            left()
                .frame(minWidth: defaults.leftMin,
                       idealWidth: clampedWidth,
                       maxWidth: defaults.leftMax)
                .layoutPriority(1)
                .background(
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.width) { _, newWidth in
                            let clamped = min(max(newWidth, defaults.leftMin), defaults.leftMax)
                            if abs(clamped - savedLeftWidth) > 2 {
                                savedLeftWidth = clamped
                            }
                        }
                    }
                )
                .onDisappear {
                    let clamped = min(max(savedLeftWidth, Double(defaults.leftMin)), Double(defaults.leftMax))
                    savedLeftWidth = clamped
                }
            right()
                .frame(minWidth: defaults.rightMin, idealWidth: 500, maxWidth: .infinity)
                .layoutPriority(0)
        }
    }
}
