import SwiftUI

extension Array where Element == RulesPanelFieldError {
    func inGroup(_ group: String) -> [RulesPanelFieldError] {
        filter { e in
            e.field == group
                || e.field.hasPrefix(group + "[")
                || e.field.hasPrefix(group + ".")
        }
    }

    func inRow(group: String, key: String) -> [RulesPanelFieldError] {
        let prefix = "\(group)[\(key)]"
        return filter { $0.field == prefix || $0.field.hasPrefix(prefix + ".") }
    }

    func hasGroup(_ group: String) -> Bool { !inGroup(group).isEmpty }
    func hasRow(group: String, key: String) -> Bool { !inRow(group: group, key: key).isEmpty }
}

extension View {
    @ViewBuilder
    func errorHighlight(_ hasError: Bool, cornerRadius: CGFloat = 8) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.red, lineWidth: hasError ? 1.5 : 0)
                .allowsHitTesting(false)
        )
    }
}
