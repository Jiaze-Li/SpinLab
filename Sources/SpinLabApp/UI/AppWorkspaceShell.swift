import SwiftUI

/// Drag gestures on the two workspace dividers must measure translation in
/// this named space, not `.local`. The dividers themselves move within the
/// `HStack` as a direct result of the translation being measured (it feeds
/// `layout.center`/`layout.right`), so a `.local` coordinate space —
/// anchored to the divider's own, moving frame — creates a feedback loop
/// between layout and drag position and reads back a corrupted delta each
/// frame (visible as jitter/oscillation). Anchoring to the stable outer
/// container instead keeps the translation delta accurate throughout the
/// drag.
private let workspaceCoordinateSpaceName = "AppWorkspaceShell"

/// The single app-wide three-pane workspace composition
/// (Navigation | Primary | Detail).
///
/// This is the only place in the app that owns the main workspace layout.
/// Inbox, Library, and Workbench never construct their own — they only
/// supply content into `primary`/`detail`. `navigation`/`primary`/`detail`
/// stay in the same SwiftUI view hierarchy as everything above this shell
/// (`RootSplitView`, the `WindowGroup` scene), so `@Environment` values —
/// `SpinLabAppState`, `\.openWindow`, and anything else injected higher up —
/// resolve normally inside pane content. There is no separate `NSHostingView`
/// root per pane and therefore no environment boundary to bridge; branch
/// *inside* `primary`/`detail` rather than around this call site.
///
/// `WorkspaceLayoutState` remains the sole owner of user width intent
/// (`leftPreferredWidth`/`rightPreferredWidth`, persisted). This view is only
/// the rendering + gesture surface: live divider drags preview a width via
/// `WorkspaceLayoutState.layout(for:leftIntent:rightIntent:)` (a pure query),
/// and only a completed drag calls `commitLeftWidth`/`commitRightWidth`.
/// Window resize, route switches, and workflow switches only ever read
/// `layout(for:)` — never mutate.
struct AppWorkspaceShell<Navigation: View, Primary: View, Detail: View>: View {
    @ViewBuilder var navigation: () -> Navigation
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var detail: () -> Detail

    @State private var layoutState = WorkspaceLayoutState()

    @GestureState private var leftDragTranslation: CGFloat = 0
    @GestureState private var rightDragTranslation: CGFloat = 0

    private let dividerThickness = WorkspaceDivider.thickness

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutState.layout(
                for: proxy.size.width,
                dividerThickness: dividerThickness,
                leftIntent: layoutState.leftPreferredWidth + leftDragTranslation,
                rightIntent: layoutState.rightPreferredWidth - rightDragTranslation
            )

            HStack(spacing: 0) {
                navigation()
                    .frame(width: layout.left)
                    .clipped()

                WorkspaceDivider()
                    .gesture(leftDragGesture(containerWidth: proxy.size.width))

                primary()
                    .frame(width: layout.center)
                    .clipped()

                WorkspaceDivider()
                    .gesture(rightDragGesture(containerWidth: proxy.size.width))

                detail()
                    .frame(width: layout.right)
                    .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .coordinateSpace(name: workspaceCoordinateSpaceName)
        }
    }

    private func leftDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(workspaceCoordinateSpaceName))
            .updating($leftDragTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let intent = layoutState.leftPreferredWidth + value.translation.width
                let effective = layoutState.layout(
                    for: containerWidth,
                    dividerThickness: dividerThickness,
                    leftIntent: intent,
                    rightIntent: nil
                )
                layoutState.commitLeftWidth(effective.left)
            }
    }

    private func rightDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(workspaceCoordinateSpaceName))
            .updating($rightDragTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let intent = layoutState.rightPreferredWidth - value.translation.width
                let effective = layoutState.layout(
                    for: containerWidth,
                    dividerThickness: dividerThickness,
                    leftIntent: nil,
                    rightIntent: intent
                )
                layoutState.commitRightWidth(effective.right)
            }
    }
}
