import SwiftUI

struct WorkbenchMeasurementsPanel: View {
    let runtime: WorkbenchSampleWorkTrackerRuntime
    @State private var sortOrder: MeasurementsSortOrder = .latestActivity

    private var sortedSummaries: [SampleWorkSummary] {
        sortOrder.sort(runtime.summaries)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                headerRow
                if let msg = runtime.lastErrorMessage {
                    errorBanner(msg)
                }
                contentArea
            }
        } label: {
            Text("Measurements")
                .font(AppFontScale.groupHeader)
        }
        .onAppear {
            if runtime.lastRefreshAt == nil && !runtime.isRefreshing {
                runtime.refresh()
            }
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: AppSpacing.sm) {
            if runtime.isRefreshing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }
            if let ts = runtime.lastRefreshAt {
                Text("Updated at \(ts.formatted(date: .omitted, time: .shortened))")
                    .font(WorkbenchUIStyle.minimumReadableFont)
                    .foregroundStyle(WorkbenchUIStyle.secondaryTextColor)
            }
            Spacer()
            Picker("Sort", selection: $sortOrder) {
                ForEach(MeasurementsSortOrder.allCases, id: \.self) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .font(WorkbenchUIStyle.minimumReadableFont)
            Button("Refresh") {
                runtime.refresh()
            }
            .font(WorkbenchUIStyle.minimumReadableFont)
            .disabled(runtime.isRefreshing)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(WorkbenchUIStyle.minimumReadableFont)
            .foregroundStyle(WorkbenchUIStyle.errorColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contentArea: some View {
        if runtime.summaries.isEmpty {
            emptyState
        } else {
            summaryList
        }
    }

    private var emptyState: some View {
        let message: String = {
            if runtime.isRefreshing { return "Loading…" }
            if runtime.lastRefreshAt == nil { return "Press Refresh to load measurement history." }
            return "No measurement sidecars found in Library."
        }()
        return Text(message)
            .font(WorkbenchUIStyle.minimumReadableFont)
            .foregroundStyle(WorkbenchUIStyle.secondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xs)
    }

    private var summaryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sortedSummaries.enumerated()), id: \.element.id) { index, summary in
                WorkbenchMeasurementsSampleRow(summary: summary)
                if index < sortedSummaries.count - 1 {
                    Divider()
                }
            }
        }
    }
}
