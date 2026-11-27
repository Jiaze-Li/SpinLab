import SwiftUI

/// AHE results area: one row per rendered Sample and metric with an explicit "Write to Sample Result…"
/// action. Nothing here writes; it only opens the confirmation panel (Task 12).
@MainActor
struct AHEResultAssignmentSection: View {
    let store: AHEWorkspaceStore
    @State private var presented: Presented?

    private struct Presented: Identifiable {
        let id = UUID()
        let sampleKey: String
        let metric: AHEResultMetric
        let candidates: [SampleResultCandidate]
    }

    var body: some View {
        // Reading the epoch keeps the rows in step with run/override changes.
        _ = store.candidateEpoch
        let keys = store.lastRenderedSampleKeys
        return Group {
            if !keys.isEmpty, store.hasAnalysisResult {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Sample Results").font(AppFontScale.groupHeader)
                    ForEach(keys, id: \.self) { key in
                        sampleBlock(key)
                    }
                    if let message = store.resultAssignmentMessage {
                        Text(message)
                            .font(WorkbenchUIStyle.controlHintFont)
                            .workbenchProbed("workbench.ahe.assign.status")
                    }
                }
                .workbenchProbed("workbench.ahe.assign.section")
                .sheet(item: $presented) { item in
                    AHEResultAssignmentSheet(
                        store: store,
                        sampleKey: item.sampleKey,
                        sampleTitle: item.sampleKey,
                        metric: item.metric,
                        candidates: item.candidates,
                        onClose: { presented = nil })
                }
            }
        }
    }

    private func sampleBlock(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(key).font(WorkbenchUIStyle.controlLabelFont)
            ForEach(AHEResultMetric.allCases, id: \.self) { metric in
                let offer = store.resultOffer(sampleKey: key, metric: metric)
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(metric.displayName).font(WorkbenchUIStyle.controlLabelFont)
                    if let computed = offer.candidates.first {
                        Text("\(AHEResultAssignmentSheet.format(computed.value)) \(computed.unit)")
                            .font(WorkbenchUIStyle.controlValueFont.monospacedDigit())
                        Button("Write to Sample Result…") {
                            store.resultAssignmentMessage = nil
                            presented = Presented(sampleKey: key, metric: metric, candidates: offer.candidates)
                        }
                        .buttonStyle(.bordered)
                        .workbenchProbed("workbench.ahe.assign.open.\(key).\(metric.rawValue)")
                    } else if let reason = offer.unavailableReason {
                        Text(reason)
                            .font(WorkbenchUIStyle.controlHintFont)
                            .foregroundStyle(WorkbenchUIStyle.secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .workbenchProbed("workbench.ahe.assign.unavailable.\(key).\(metric.rawValue)")
                    }
                }
            }
        }
    }
}
