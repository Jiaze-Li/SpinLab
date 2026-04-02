import SwiftUI

struct LibraryExistingDrawerSampleSectionView: View {
    let level2HeaderFont: Font
    let level3HeaderFont: Font
    let selectedPrefix: String?
    let selectedBatchId: String?
    let selectedSampleId: String?
    let selectedExistingBatchSamples: [LibrarySample]
    let onSelectSample: (LibrarySample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Existing Drawer Samples")
                .font(level2HeaderFont)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let selectedPrefix, let selectedBatchId {
                        HStack {
                            Text("Batch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(selectedPrefix)/\(selectedBatchId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedExistingBatchSamples.isEmpty {
                            Text("No samples found in selected drawer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(selectedExistingBatchSamples) { sample in
                                        Button {
                                            onSelectSample(sample)
                                        } label: {
                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                Text(sample.substrateDisplay)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(6)
                                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(selectedSampleId == sample.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(height: 220)
                        }
                    } else {
                        Text("Select a batch in the left Library tree to choose its samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Sample List")
                    .font(level3HeaderFont)
            }
        }
    }
}

struct LibrarySampleDetailHeaderView: View {
    let isEditingSelectedSample: Bool
    let sampleEditIsDirty: Bool
    let sampleEditIsSaving: Bool
    let canEditSelectedLibrarySample: Bool
    let sampleEditError: String?
    let sampleEditMessage: String?

    let onLoadGlobalManualLogs: () -> Void
    let onLoadMetadataSyncLogs: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: () -> Void
    let onBeginEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sample Detail")
                    .font(.title2.bold())
                Spacer()
                Button("Numeric日志") {
                    onLoadGlobalManualLogs()
                }
                Button("Metadata日志") {
                    onLoadMetadataSyncLogs()
                }
                if isEditingSelectedSample {
                    Button("Cancel") {
                        onCancelEdit()
                    }
                    Button("Save") {
                        onSaveEdit()
                    }
                    .disabled(!sampleEditIsDirty || sampleEditIsSaving)
                } else {
                    Button("Edit") {
                        onBeginEdit()
                    }
                    .disabled(!canEditSelectedLibrarySample)
                }
            }

            if let sampleEditError {
                Text(sampleEditError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let sampleEditMessage {
                Text(sampleEditMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LibraryMeasurementsDoneSection: View {
    let measurements: [AppliedMeasurement]
    let workflowDisplayNameByID: [String: String]
    let workflowConditionOrderByID: [String: [String]]
    @State private var isExpanded = true
    @State private var hoverRevealTask: Task<Void, Never>?
    @State private var revealedFileNameMeasurementID: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if measurements.isEmpty {
                Text("No measurements applied yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(measurements) { measurement in
                        measurementRow(measurement)
                    }
                }
            }
        } label: {
            Text("Measurements Done")
                .font(.title3.weight(.semibold))
        }
        .textSelection(.enabled)
        .onDisappear {
            hoverRevealTask?.cancel()
            hoverRevealTask = nil
            revealedFileNameMeasurementID = nil
        }
    }

    @ViewBuilder
    private func measurementRow(_ measurement: AppliedMeasurement) -> some View {
        let normalizedWorkflowID = measurement.workflow.trimmingCharacters(in: .whitespacesAndNewlines)
        let registryDisplayName = workflowDisplayNameByID[normalizedWorkflowID]
            ?? workflowDisplayNameByID.first(where: {
                $0.key.caseInsensitiveCompare(normalizedWorkflowID) == .orderedSame
            })?.value
        let displayWorkflow = registryDisplayName
            ?? (measurement.workflowDisplayName.isEmpty ? measurement.workflow : measurement.workflowDisplayName)
        let conditionOrder = workflowConditionOrderByID[normalizedWorkflowID]
            ?? workflowConditionOrderByID.first(where: {
                $0.key.caseInsensitiveCompare(normalizedWorkflowID) == .orderedSame
            })?.value
            ?? []
        let orderedConditionPairs = orderedConditions(
            measurement.conditions,
            preferredOrder: conditionOrder
        )
        VStack(alignment: .leading, spacing: 3) {
            Text(displayWorkflow)
                .font(.callout.weight(.semibold))
            if !orderedConditionPairs.isEmpty {
                HStack(spacing: 8) {
                ForEach(orderedConditionPairs, id: \.key) { pair in
                    Text(pair.value.isEmpty ? "—" : pair.value)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                }
            }
            if revealedFileNameMeasurementID == measurement.id {
                Text(measurement.sourceFileName)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07)))
        .onHover { isHovering in
            if isHovering {
                scheduleFileNameReveal(for: measurement.id)
            } else {
                cancelFileNameReveal(for: measurement.id)
            }
        }
    }

    private func orderedConditions(
        _ conditions: [String: String],
        preferredOrder: [String]
    ) -> [(key: String, value: String)] {
        guard !conditions.isEmpty else { return [] }
        let indexByKey = Dictionary(
            uniqueKeysWithValues: preferredOrder.enumerated().map { ($0.element.lowercased(), $0.offset) }
        )
        return conditions.sorted { lhs, rhs in
            let leftIndex = indexByKey[lhs.key.lowercased()]
            let rightIndex = indexByKey[rhs.key.lowercased()]
            switch (leftIndex, rightIndex) {
            case let (l?, r?):
                if l != r { return l < r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
    }

    private func scheduleFileNameReveal(for measurementID: String) {
        hoverRevealTask?.cancel()
        hoverRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            revealedFileNameMeasurementID = measurementID
        }
    }

    private func cancelFileNameReveal(for measurementID: String) {
        hoverRevealTask?.cancel()
        hoverRevealTask = nil
        if revealedFileNameMeasurementID == measurementID {
            revealedFileNameMeasurementID = nil
        }
    }
}
