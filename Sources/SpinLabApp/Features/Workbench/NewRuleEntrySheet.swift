import SwiftUI

struct NewRuleEntrySheet: View {
    let kind: RuleEntryKind
    let existingEntries: [RuleEntry]
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .tokenMap ? "New Token-Map Entry" : "New Unit-Suffix Entry")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Wafer Type", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            GroupBox("Save Preview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Binding: \(resolvedBindingPreview)")
                        .font(.caption.monospaced())
                    if let reservedNotice {
                        Text(reservedNotice)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(bindingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    commit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func commit() {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLabel.isEmpty else {
            validationError = "Label cannot be empty."
            return
        }
        let normalizedID = nextRuleID(for: normalizedLabel)
        let existsSameKind = existingEntries.contains {
            $0.ruleID.caseInsensitiveCompare(normalizedID) == .orderedSame &&
            $0.kind == kind
        }
        guard !existsSameKind else {
            validationError = "This label already has a \(kind.rawValue) entry."
            return
        }

        onAdd(normalizedID, normalizedLabel)
        dismiss()
    }

    private var resolvedBindingPreview: String {
        let normalizedID = nextRuleID(for: label)
        guard !normalizedID.isEmpty else {
            return kind == .tokenMap ? "conditions.tokenMapRules.<rule_id>" : "conditions.extraConditions.<rule_id>"
        }
        switch kind {
        case .unitSuffix:
            return "conditions.extraConditions.\(normalizedID)"
        case .tokenMap:
            return "conditions.tokenMapRules.\(normalizedID)"
        case .customReadOnly:
            return "n/a"
        }
    }

    private var bindingDescription: String {
        switch kind {
        case .unitSuffix:
            return "Unit-suffix entries match tokens like 20K/1mA and are stored as regex-backed condition patterns."
        case .tokenMap:
            return "Token-map entries match text tokens and map them to normalized condition values for workflow fields."
        case .customReadOnly:
            return "Read-only entries cannot be created from this dialog."
        }
    }

    private var reservedNotice: String? { nil }

    private func nextRuleID(for label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var base = trimmed
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if base.isEmpty {
            base = "rule"
        }
        if base.first?.isNumber == true {
            base = "rule_\(base)"
        }

        let existingIDs = Set(existingEntries.map { $0.ruleID.lowercased() })
        if !existingIDs.contains(base) {
            return base
        }

        var suffix = 2
        while existingIDs.contains("\(base)_\(suffix)") {
            suffix += 1
        }
        return "\(base)_\(suffix)"
    }
}
