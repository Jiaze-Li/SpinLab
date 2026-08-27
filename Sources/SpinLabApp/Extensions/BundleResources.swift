import Foundation

private final class SpinLabResourceMarker {}

extension Bundle {

    /// Resilient locator for the SwiftPM `.process("config")` resource bundle
    /// (`SpinLab_SpinLabApp.bundle`).
    ///
    /// The compiler-synthesised `Bundle.module` accessor produced by the Swift 6.3
    /// toolchain resolves the resource bundle *only* against
    /// `Bundle.main.bundleURL` (plus a hard-coded absolute build-directory path).
    /// For a packaged `.app` `Bundle.main.bundleURL` is the wrapper root
    /// (`SpinLab.app/`), and placing a loose `.bundle` there makes `codesign`
    /// emit "unsealed contents present in the bundle root" and produce a
    /// malformed signature. The only codesign-safe location is
    /// `SpinLab.app/Contents/Resources/`, which the synthesised accessor never
    /// checks — so `Bundle.module` hits `fatalError` at launch.
    ///
    /// This accessor additionally checks `Bundle.main.resourceURL`
    /// (`Contents/Resources` in a packaged app) and the framework bundle of a
    /// marker class, so the same resource-loading semantics hold under
    /// `swift run`, `swift test`, and the packaged `.app`. It falls back to
    /// `Bundle.module` if nothing else matches, preserving prior behaviour.
    static let spinLabConfig: Bundle = {
        let bundleName = "SpinLab_SpinLabApp.bundle"

        var searchBases: [URL] = []
        if let url = Bundle.main.resourceURL { searchBases.append(url) }
        searchBases.append(Bundle.main.bundleURL)
        let marker = Bundle(for: SpinLabResourceMarker.self)
        if let url = marker.resourceURL { searchBases.append(url) }
        searchBases.append(marker.bundleURL)

        for base in searchBases {
            let candidate = base.appendingPathComponent(bundleName)
            if FileManager.default.fileExists(atPath: candidate.path),
               let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return .module
    }()
}
