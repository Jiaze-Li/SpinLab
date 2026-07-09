import SwiftUI

// MARK: - Key-level bindings into shared style dictionaries

/// Narrows a `Binding<[String: String]>` (e.g. `globalPlotDefaults`,
/// `chartStyleOverrides`) down to a single key, so a sub-control (a single font
/// picker, a single style menu) only depends on that key's value rather than the
/// whole dictionary. Writes still land in the same shared dictionary — the saved
/// format is unchanged.
extension Binding where Value == [String: String] {
    func valueBinding(forKey key: String) -> Binding<String?> {
        Binding<String?>(
            get: { self.wrappedValue[key] },
            set: { newValue in
                if let newValue {
                    self.wrappedValue[key] = newValue
                } else {
                    self.wrappedValue.removeValue(forKey: key)
                }
            }
        )
    }
}
