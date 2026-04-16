import SwiftUI

struct ApplyProgressOverlay: View {
    let progress: ApplyProgressState

    private var fractionCompleted: Double {
        guard progress.totalCount > 0 else {
            return 0
        }
        return Double(progress.processedCount) / Double(progress.totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Applying Pending Imports")
                .font(.headline)
            Text("\(progress.processedCount)/\(progress.totalCount)")
                .font(.title3.monospacedDigit().weight(.semibold))
            ProgressView(value: fractionCompleted, total: 1.0)
                .progressViewStyle(.linear)
            if !progress.currentFileName.isEmpty {
                Text("Current: \(progress.currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Applied \(progress.appliedCount) · Skipped \(progress.skippedCount) · Failed \(progress.failedCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 10, y: 4)
    }
}

struct ImportProgressOverlay: View {
    let progress: ImportProgressState

    private var fractionCompleted: Double {
        guard progress.totalCount > 0 else {
            return 0
        }
        return Double(progress.processedCount) / Double(progress.totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Importing Files")
                .font(.headline)
            Text("\(progress.processedCount)/\(progress.totalCount)")
                .font(.title3.monospacedDigit().weight(.semibold))
            ProgressView(value: fractionCompleted, total: 1.0)
                .progressViewStyle(.linear)
            if !progress.currentFileName.isEmpty {
                Text("Current: \(progress.currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if progress.failedCount > 0 {
                Text("Failed \(progress.failedCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(radius: 10, y: 4)
    }
}
