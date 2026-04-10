import SwiftUI

/// Reusable hover-popover behavior: hover to show, leave to dismiss (with grace period).
///
/// Shared by Library measurement rows and Workbench chart canvas.
/// Handles:
/// - Configurable show delay (time before popover appears)
/// - Configurable dismiss delay (grace period for cursor to travel to popover)
/// - Panel hover tracking (popover stays while cursor is over it)
/// - Dialog guard (popover stays while a confirmation dialog is active inside it)
struct HoverPopoverModifier<PopoverContent: View>: ViewModifier {
    let showDelay: Duration
    let dismissDelay: Duration
    let arrowEdge: Edge
    let isEnabled: Bool
    var onPresentedChanged: ((Bool) -> Void)? = nil
    @ViewBuilder let popoverContent: (_ onHoverChanged: @escaping (Bool) -> Void,
                                       _ onDialogActiveChanged: @escaping (Bool) -> Void) -> PopoverContent

    @State private var isPopoverPresented = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHoveringPanel = false
    @State private var isDialogActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, isEnabled {
                    scheduleShow()
                } else {
                    scheduleDismiss()
                }
            }
            .popover(isPresented: $isPopoverPresented, arrowEdge: arrowEdge) {
                popoverContent(
                    { isHovering in
                        isHoveringPanel = isHovering
                        if isHovering {
                            hoverTask?.cancel()
                        } else {
                            scheduleDismiss()
                        }
                    },
                    { active in
                        isDialogActive = active
                    }
                )
            }
            .onDisappear {
                hoverTask?.cancel()
                hoverTask = nil
                isPopoverPresented = false
            }
            .onChange(of: isPopoverPresented) { _, newValue in
                onPresentedChanged?(newValue)
            }
    }

    private func scheduleShow() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: showDelay)
            guard !Task.isCancelled else { return }
            isPopoverPresented = true
        }
    }

    private func scheduleDismiss() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: dismissDelay)
            guard !Task.isCancelled else { return }
            guard !isHoveringPanel, !isDialogActive else { return }
            isPopoverPresented = false
        }
    }
}

extension View {
    /// Attaches a hover-triggered popover with configurable timing.
    func hoverPopover<Content: View>(
        showDelay: Duration = .seconds(1),
        dismissDelay: Duration = .milliseconds(500),
        arrowEdge: Edge = .trailing,
        isEnabled: Bool = true,
        onPresentedChanged: ((Bool) -> Void)? = nil,
        @ViewBuilder content: @escaping (
            _ onHoverChanged: @escaping (Bool) -> Void,
            _ onDialogActiveChanged: @escaping (Bool) -> Void
        ) -> Content
    ) -> some View {
        modifier(HoverPopoverModifier(
            showDelay: showDelay,
            dismissDelay: dismissDelay,
            arrowEdge: arrowEdge,
            isEnabled: isEnabled,
            onPresentedChanged: onPresentedChanged,
            popoverContent: content
        ))
    }
}
