import AppKit
import SwiftUI

struct SampleIDRulesSection: View {
    let store: RulesManagementStore

    @State private var draft = SampleIDRulesFileDraft(version: 1, patterns: [])
    @State private var saveErrors: [RulesPanelFieldError] = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            saveButton

            Text(RulesPanelSection.sampleID.displayName)
                .font(AppFontScale.sectionHeader)

            HStack(spacing: AppSpacing.md) {
                Button("Add Pattern") {
                    draft.patterns.append("")
                    pushDraftUpdate()
                }
                .buttonStyle(.bordered)

                Button("Paste Lines") {
                    pastePatternsFromClipboard()
                }
                .buttonStyle(.bordered)

                Button("Deduplicate") {
                    deduplicatePatterns()
                }
                .buttonStyle(.bordered)
            }

            List {
                ForEach(Array(draft.patterns.enumerated()), id: \.offset) { index, _ in
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        RegexField(title: "Pattern", text: bindingForPattern(at: index))
                        Button("Delete") {
                            draft.patterns.remove(at: index)
                            pushDraftUpdate()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(minHeight: 260)

            if !saveErrors.isEmpty {
                validationErrorBlock
            }

            saveButton
        }
        .onAppear {
            if let existing = store.sampleIDDraft {
                draft = existing
            }
        }
    }

    private var saveButton: some View {
        Button("Save") {
            pushDraftUpdate()
            let outcome = store.saveCurrent()
            handleSaveOutcome(outcome)
        }
        .disabled(hasValidationErrors)
    }

    private var hasValidationErrors: Bool {
        !regexCompileErrors.isEmpty || !saveErrors.isEmpty
    }

    private var regexCompileErrors: [Int: String] {
        var errors: [Int: String] = [:]
        for (index, pattern) in draft.patterns.enumerated() {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            do {
                _ = try NSRegularExpression(pattern: trimmed)
            } catch {
                errors[index] = error.localizedDescription
            }
        }
        return errors
    }

    private var validationErrorBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Validation Errors")
                .font(AppFontScale.groupHeader)
                .foregroundStyle(.red)
            ForEach(saveErrors) { error in
                Text("• [\(error.field)] \(error.message)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func bindingForPattern(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.patterns.indices.contains(index) else { return "" }
                return draft.patterns[index]
            },
            set: { newValue in
                guard draft.patterns.indices.contains(index) else { return }
                draft.patterns[index] = newValue
                pushDraftUpdate()
            }
        )
    }

    private func pastePatternsFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return }
        draft.patterns.append(contentsOf: lines)
        pushDraftUpdate()
    }

    private func deduplicatePatterns() {
        var seen = Set<String>()
        var unique: [String] = []
        for pattern in draft.patterns {
            if seen.insert(pattern).inserted {
                unique.append(pattern)
            }
        }
        draft.patterns = unique
        pushDraftUpdate()
    }

    private func pushDraftUpdate() {
        store.updateSampleID(draft)
        saveErrors = []
    }

    private func handleSaveOutcome(_ outcome: RulesPanelSaveOutcome) {
        switch outcome {
        case .saved:
            saveErrors = []
        case .validationFailed(let errors):
            saveErrors = errors
        case .externalConflict(let checksum):
            saveErrors = [RulesPanelFieldError(field: "externalConflict", message: "External change detected (\(checksum)). Reload and retry.")]
        case .ioError(let error):
            saveErrors = [RulesPanelFieldError(field: "ioError", message: error.localizedDescription)]
        }
    }
}
