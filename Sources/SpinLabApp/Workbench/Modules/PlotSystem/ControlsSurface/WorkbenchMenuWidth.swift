import AppKit
import SwiftUI

/// Content-fit width of a menu Picker (`04_UI_RULES.md` VC-8):
/// widest option as a real SwiftUI menu Picker renders it (real font, system arrows and insets,
/// measured by hosting that Picker with the same control size and environment font) + the shared comfort padding. It
/// depends on the option set and control size only, never on the current selection, so the control
/// does not change width when its value changes.
@MainActor
enum WorkbenchMenuWidth {
    private struct Key: Hashable {
        let titles: [String]
        let controlSize: ControlSize
        let font: Font?
    }

    private static var cache: [Key: CGFloat] = [:]

    private struct Probe: View {
        let titles: [String]
        @State private var selection = 0
        var body: some View {
            Picker("", selection: $selection) {
                ForEach(titles.indices, id: \.self) { Text(titles[$0]).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    /// Native Picker width for `titles`: the widest title plus the system arrows and insets.
    static func nativeWidth(_ titles: [String], controlSize: ControlSize = .regular, font: Font? = nil) -> CGFloat {
        let key = Key(titles: titles, controlSize: controlSize, font: font)
        if let cached = cache[key] { return cached }
        let host = NSHostingView(rootView: Probe(titles: titles).environment(\.controlSize, controlSize).environment(\.font, font))
        let width = ceil(host.fittingSize.width)
        cache[key] = width
        return width
    }

    /// Final menu width: native width + `WorkbenchInputWidth.menuComfortPadding`, never below the
    /// VC-4 menu minimum.
    static func fit(_ titles: [String], controlSize: ControlSize = .regular, font: Font? = nil) -> CGFloat {
        max(nativeWidth(titles, controlSize: controlSize, font: font) + WorkbenchInputWidth.menuComfortPadding, WorkbenchInputWidth.menuMinimum)
    }
}

private struct WorkbenchContentFitMenuModifier: ViewModifier {
    let titles: [String]
    @Environment(\.controlSize) private var controlSize
    @Environment(\.font) private var font

    func body(content: Content) -> some View {
        content.frame(width: WorkbenchMenuWidth.fit(titles, controlSize: controlSize, font: font), alignment: .leading)
    }
}

extension View {
    /// Sizes a menu Picker to its longest option (see `WorkbenchMenuWidth`). Apply before
    /// `.workbenchControl(.menu)` so the probe measures the control itself.
    func workbenchContentFitMenu(_ titles: [String]) -> some View {
        modifier(WorkbenchContentFitMenuModifier(titles: titles))
    }
}
