import AppKit
import SwiftUI

struct RegexField: View {
    let title: String
    @Binding var text: String

    @State private var compileErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .onAppear(perform: validate)
                .onChange(of: text) { _, _ in validate() }

            if let compileErrorMessage {
                Text(compileErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    var currentError: String? { compileErrorMessage }

    private func validate() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            compileErrorMessage = nil
            return
        }

        do {
            _ = try NSRegularExpression(pattern: trimmed)
            compileErrorMessage = nil
        } catch {
            compileErrorMessage = error.localizedDescription
        }
    }
}
