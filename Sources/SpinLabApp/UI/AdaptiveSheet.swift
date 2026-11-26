import AppKit
import SwiftUI

/// Where a sheet may grow: the visible area of the screen its window is on, and the window's
/// current top edge. Both are AppKit (bottom-left origin) y values.
///
/// Sheets hang from the top edge of their parent window and grow downward, so the room left
/// below the top edge is what limits the height, not the screen's total height.
struct AdaptiveSheetScreenArea: Equatable {
    /// Lowest usable y of the screen (above the Dock when it is at the bottom).
    var visibleMinY: CGFloat
    /// Highest usable y of the screen (below the menu bar).
    var visibleMaxY: CGFloat
    /// Top edge of the sheet window.
    var windowTopY: CGFloat

    init(visibleMinY: CGFloat, visibleMaxY: CGFloat, windowTopY: CGFloat) {
        self.visibleMinY = visibleMinY
        self.visibleMaxY = visibleMaxY
        self.windowTopY = windowTopY
    }

    /// Used until the window is known: assume the sheet starts a little below the top of the
    /// main screen.
    static var fallback: AdaptiveSheetScreenArea {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 800)
        return AdaptiveSheetScreenArea(
            visibleMinY: visible.minY,
            visibleMaxY: visible.maxY,
            windowTopY: visible.maxY - AppSpacing.xxl * 3)
    }

    /// The area for a live window, from the screen that window is actually on.
    static func of(window: NSWindow) -> AdaptiveSheetScreenArea {
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 800)
        return AdaptiveSheetScreenArea(
            visibleMinY: visible.minY, visibleMaxY: visible.maxY, windowTopY: window.frame.maxY)
    }
}

/// Pure sizing rules, kept free of views so they can be tested for any screen height.
enum AdaptiveSheetLayout {
    /// Gap kept between the sheet's bottom edge and the bottom of the visible area.
    static let bottomMargin: CGFloat = AppSpacing.xxl
    /// Height used for the middle area before the first measurement, so the sheet never appears
    /// collapsed and then jumps.
    static let initialMiddleHeight: CGFloat = AppSpacing.xxl * 10
    /// Header + actions + dividers assumed before they are measured.
    static let assumedChromeHeight: CGFloat = AppSpacing.xxl * 4

    /// Largest height of the middle area such that the sheet's bottom edge, including the pinned
    /// actions, stays inside the visible area with `bottomMargin` to spare.
    ///
    /// `chromeHeight` is everything that is not the middle area (header, actions, dividers).
    /// The pinned actions always win over the middle area: if the room left is smaller than the
    /// chrome itself, the middle area shrinks to zero rather than pushing the buttons off screen.
    static func maxMiddleHeight(area: AdaptiveSheetScreenArea, chromeHeight: CGFloat) -> CGFloat {
        let top = min(area.windowTopY, area.visibleMaxY)
        let room = top - area.visibleMinY - bottomMargin - chromeHeight
        return max(room, 0)
    }

    /// Height of the middle area for a measured content height.
    static func middleHeight(measured: CGFloat?, cap: CGFloat) -> CGFloat {
        min(measured ?? min(initialMiddleHeight, cap), cap)
    }

    /// True when a sheet with this middle height keeps its bottom edge inside the visible area.
    static func fitsScreen(area: AdaptiveSheetScreenArea, chromeHeight: CGFloat, middleHeight: CGFloat) -> Bool {
        let top = min(area.windowTopY, area.visibleMaxY)
        return top - (chromeHeight + middleHeight) >= area.visibleMinY
    }
}

/// Shared layout for sheets and dialogs (specs/04_UI_RULES.md, "Sheets and Dialogs").
///
/// Layout only: a pinned header, a middle content area and pinned actions. Business state,
/// validation, error display and button behaviour stay with the caller.
///
/// - Short content: the middle area is exactly as tall as its content, so it shows no scroll
///   bar and has nothing to scroll.
/// - Content that grows (a disclosure expands): the sheet grows with it.
/// - Content taller than the room below the sheet's top edge on its own screen: only the
///   middle area scrolls; header and actions stay on screen.
///
/// The middle area is always one `ScrollView` whose height is the measured content height
/// capped by the room left on the window's own screen. The view identity never changes between
/// the short and long cases, so text-field input and focus survive the content crossing the cap.
struct AdaptiveSheet<Header: View, Content: View, Actions: View>: View {
    let minWidth: CGFloat
    /// Replaces the live window/screen probe. Intended for tests and previews.
    let screenAreaOverride: AdaptiveSheetScreenArea?
    private let header: Header
    private let content: Content
    private let actions: Actions

    @State private var measuredContentHeight: CGFloat?
    @State private var headerHeight: CGFloat?
    @State private var actionsHeight: CGFloat?
    @State private var probedArea: AdaptiveSheetScreenArea?

    init(
        minWidth: CGFloat,
        screenArea: AdaptiveSheetScreenArea? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.minWidth = minWidth
        self.screenAreaOverride = screenArea
        self.header = header()
        self.content = content()
        self.actions = actions()
    }

    private var area: AdaptiveSheetScreenArea {
        screenAreaOverride ?? probedArea ?? .fallback
    }

    /// Header, actions and the two dividers.
    private var chromeHeight: CGFloat {
        guard let headerHeight, let actionsHeight else { return AdaptiveSheetLayout.assumedChromeHeight }
        return headerHeight + actionsHeight + 2
    }

    var body: some View {
        let cap = AdaptiveSheetLayout.maxMiddleHeight(area: area, chromeHeight: chromeHeight)
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.vertical, AppSpacing.lg)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }

            Divider()

            ScrollView {
                content
                    .padding(AppSpacing.xxl)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                        measuredContentHeight = $0
                    }
            }
            .frame(height: AdaptiveSheetLayout.middleHeight(measured: measuredContentHeight, cap: cap))

            Divider()

            actions
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.vertical, AppSpacing.lg)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { actionsHeight = $0 }
        }
        .frame(minWidth: minWidth)
        .background {
            if screenAreaOverride == nil {
                SheetScreenProbe { newArea in
                    // Never change state inside a view update; hop to the next turn.
                    DispatchQueue.main.async { if probedArea != newArea { probedArea = newArea } }
                }
            }
        }
    }
}

/// Reports the screen area of the window this view lives in, and updates it when the window
/// moves, changes screen or the screen layout changes.
private struct SheetScreenProbe: NSViewRepresentable {
    let onChange: (AdaptiveSheetScreenArea) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ProbeView: NSView {
        var onChange: ((AdaptiveSheetScreenArea) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification, NSWindow.didResizeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.report()
                })
            }
            observers.append(center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.report() })
            report()
            // A sheet's final position is set just after it is attached.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        func report() {
            guard let window else { return }
            onChange?(AdaptiveSheetScreenArea.of(window: window))
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
