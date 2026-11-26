import AppKit
import SwiftUI

/// Shared layout for sheets and dialogs (specs/04_UI_RULES.md, "Sheets and Dialogs").
///
/// Layout only: a pinned header, a middle content area and pinned actions. Business state,
/// validation, error display and button behaviour stay with the caller.
///
/// - Short content: the middle area is exactly as tall as its content, so it shows no scroll
///   bar and has nothing to scroll.
/// - Content that grows (a disclosure expands): the sheet grows with it.
/// - Content taller than the screen allows: only the middle area scrolls; header and actions
///   stay visible.
///
/// The middle area is always one `ScrollView` whose height is the measured content height
/// capped at `maxContentHeight`. The view identity never changes between the short and long
/// cases, so text-field input and focus survive the content crossing the cap.
struct AdaptiveSheet<Header: View, Content: View, Actions: View>: View {
    let minWidth: CGFloat
    /// Overrides the screen-derived cap. Intended for tests and previews.
    let maxContentHeightOverride: CGFloat?
    private let header: Header
    private let content: Content
    private let actions: Actions

    @State private var measuredContentHeight: CGFloat?

    init(
        minWidth: CGFloat,
        maxContentHeight: CGFloat? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.minWidth = minWidth
        self.maxContentHeightOverride = maxContentHeight
        self.header = header()
        self.content = content()
        self.actions = actions()
    }

    /// Room left for the middle area after the pinned header, actions and a margin to the
    /// screen edges. Batch 1 uses `NSScreen.main`; a window-aware probe is only added if
    /// multi-screen GUI evidence shows a real problem.
    static var screenMaxContentHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return cappedHeight(screenVisibleHeight: screen)
    }

    static func cappedHeight(screenVisibleHeight: CGFloat) -> CGFloat {
        max(screenVisibleHeight - AppSpacing.xxl * 8, AppSpacing.xxl * 10)
    }

    /// Height of the middle area. Before the first measurement it uses the lower bound rather
    /// than 0, so the sheet never appears collapsed and then jumps.
    static func middleHeight(measured: CGFloat?, cap: CGFloat) -> CGFloat {
        min(measured ?? AppSpacing.xxl * 10, cap)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.vertical, AppSpacing.lg)

            Divider()

            ScrollView {
                content
                    .padding(AppSpacing.xxl)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                        measuredContentHeight = $0
                    }
            }
            .frame(height: Self.middleHeight(
                measured: measuredContentHeight,
                cap: maxContentHeightOverride ?? Self.screenMaxContentHeight))

            Divider()

            actions
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.vertical, AppSpacing.lg)
        }
        .frame(minWidth: minWidth)
    }
}
