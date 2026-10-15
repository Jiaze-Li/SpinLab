import SwiftUI

/// Global "Transparent Background" checkbox. Stored in the shared plot defaults (not workflow
/// pack state), so it applies to every workflow's PNG/workspace render. Off = white canvas.
struct SharedPlotTransparentBackgroundToggle: View {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: (() -> Void)?

    var body: some View {
        Toggle("Transparent", isOn: Binding(
            get: { globalPlotDefaults["transparentBackground"] == "true" },
            set: { isOn in
                if isOn {
                    globalPlotDefaults["transparentBackground"] = "true"
                } else {
                    globalPlotDefaults.removeValue(forKey: "transparentBackground")
                }
                onStyleChange?()
            }
        ))
        .toggleStyle(.checkbox)
        .help("Transparent Background: export PNG without the white canvas.")
    }
}
