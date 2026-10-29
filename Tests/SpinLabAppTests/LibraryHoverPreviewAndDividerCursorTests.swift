import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

@MainActor
@Suite("LibraryHoverPreviewAndDividerCursor")
struct LibraryHoverPreviewAndDividerCursorTests {

    private func reference() -> WorkbenchResultReference {
        WorkbenchResultReference(
            chartIdentityKey: "k", chartImagePath: "charts/a.png", manifestPath: "charts/a.json",
            workflowID: "afm", generatedAt: Date(timeIntervalSince1970: 0), tabKey: nil
        )
    }

    private func row(_ refs: [WorkbenchResultReference]) -> some View {
        Text("row").measurementPlotHoverPreview(
            references: refs, libraryRootURL: nil, onDelete: { _ in }, onPresentedChanged: { _ in }
        )
    }

    private func mountsHoverPopover(_ view: some View) -> Bool {
        func walk(_ value: Any, depth: Int) -> Bool {
            if depth > 14 { return false }
            let name = String(describing: type(of: value))
            if name.prefix(while: { $0 != "<" }) == "HoverPopoverModifier" { return true }
            return Mirror(reflecting: value).children.contains { walk($0.value, depth: depth + 1) }
        }
        return walk(view, depth: 0)
    }

    @Test("predicate: only rows with linked charts get a preview")
    func predicate() {
        #expect(!LibraryMeasurementsDoneSection.shouldMountHoverPreview(references: []))
        #expect(LibraryMeasurementsDoneSection.shouldMountHoverPreview(references: [reference()]))
    }

    @Test("a row without charts has no hover popover in its view tree")
    func notMountedWithoutCharts() {
        #expect(!mountsHoverPopover(row([])))
    }

    @Test("a row with charts keeps the existing hover popover")
    func mountedWithCharts() {
        #expect(mountsHoverPopover(row([reference()])))
    }

    @Test("divider cursor view never intercepts clicks or drags")
    func cursorViewIsTransparentToHits() {
        let view = ResizeCursorRectView(frame: NSRect(x: 0, y: 0, width: 9, height: 100))
        #expect(view.hitTest(NSPoint(x: 4, y: 50)) == nil)
    }

    @Test("divider cursor view installs and refreshes its rect inside a window without error")
    func cursorViewWorksInWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let view = ResizeCursorRectView(frame: NSRect(x: 0, y: 0, width: 9, height: 100))
        window.contentView?.addSubview(view)
        view.resetCursorRects()
        view.setFrameSize(NSSize(width: 9, height: 150))
        #expect(view.window === window)
        #expect(ResizeCursorRectView.cursor == NSCursor.resizeLeftRight)
    }

    @Test("the divider no longer pairs NSCursor push/pop")
    func noPushPop() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/SpinLabApp/UI/WorkspaceDivider.swift"), encoding: .utf8)
        #expect(!source.contains(".push()"))
        #expect(!source.contains("NSCursor.pop"))
        #expect(source.contains("static let thickness: CGFloat = 9"))
    }
}
