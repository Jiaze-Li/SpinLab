import SwiftUI

/// Confirmation panel for assigning one AHE metric of one Sample to an existing Result Definition
/// (Task 12). Source Sample is read-only; Definition and (when a correction exists) the value are chosen
/// explicitly. Nothing is written until "Write" is pressed, and only through `LibraryResultService`.
@MainActor
struct AHEResultAssignmentSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    let store: AHEWorkspaceStore
    let sampleKey: String
    let sampleTitle: String
    let metric: AHEResultMetric
    /// Offered at the moment the panel was opened. Staleness is judged against the live store.
    let candidates: [SampleResultCandidate]
    let onClose: () -> Void

    private struct Context {
        var service: LibraryResultService
        var rootURL: URL
        var sample: LibrarySample
        var definitions: [ResultDefinition]
        var leaseSessionID: String
    }

    @State private var context: Context?
    @State private var loadError: String?
    @State private var selectedCandidateID: String?
    @State private var selectedDefinitionID: String?
    @State private var currentOnDisk: Double?
    @State private var errorMessage: String?
    @State private var didWrite = false

    private var selectedCandidate: SampleResultCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    private var selectedDefinition: ResultDefinition? {
        context?.definitions.first { $0.definitionID == selectedDefinitionID }
    }

    private var conversion: ResultUnitConversion.Outcome? {
        guard let candidate = selectedCandidate, let definition = selectedDefinition else { return nil }
        return ResultUnitConversion.convert(candidate.value, from: candidate.unit, to: definition.unit)
    }

    private var isStale: Bool {
        // Reads the store's epoch so the panel re-evaluates when the run or override changes.
        _ = store.candidateEpoch
        return candidates.contains { !store.isCurrent($0) }
    }

    private var canConfirm: Bool {
        guard !didWrite, !isStale, loadError == nil,
              !LibraryWriteLease.shared.isReadOnly,
              selectedCandidate != nil, selectedDefinition != nil,
              conversion?.writableValue != nil else { return false }
        return true
    }

    var body: some View {
        AdaptiveSheet(minWidth: 520) {
            Text("Write \(metric.displayName) to Sample Result")
                .font(AppFontScale.groupHeader)
        } content: {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                sourceBlock
                if let loadError {
                    Text(loadError)
                        .font(WorkbenchUIStyle.controlValueFont)
                        .foregroundStyle(WorkbenchUIStyle.errorColor)
                        .workbenchProbed("workbench.ahe.assign.loadError")
                } else if context != nil {
                    candidateBlock
                    definitionBlock
                    previewBlock
                }
                if isStale {
                    Text("The analysis changed after this panel was opened. Close it and open it again to continue.")
                        .font(WorkbenchUIStyle.controlValueFont)
                        .foregroundStyle(WorkbenchUIStyle.warningColor)
                        .workbenchProbed("workbench.ahe.assign.stale")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(WorkbenchUIStyle.controlValueFont)
                        .foregroundStyle(WorkbenchUIStyle.errorColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .workbenchProbed("workbench.ahe.assign.error")
                }
            }
        } actions: {
            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .workbenchProbed("workbench.ahe.assign.cancel")
                Button(currentOnDisk == nil ? "Write" : "Replace Value") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfirm)
                    .workbenchProbed("workbench.ahe.assign.confirm")
            }
        }
        .task { prepare() }
        .onChange(of: selectedDefinitionID) { _, _ in refreshCurrentValue() }
    }

    // MARK: - Blocks

    private var sourceBlock: some View {
        let first = candidates.first
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            labeledRow("Sample", context?.sample.displayName ?? sampleTitle)
            if let first {
                labeledRow("Input", first.inputSummary)
                labeledRow("Conditions", Self.conditionsText(first.conditions))
            }
        }
        .workbenchProbed("workbench.ahe.assign.source")
    }

    private var candidateBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Value").font(WorkbenchUIStyle.controlLabelFont)
            ForEach(candidates) { candidate in
                Button {
                    selectedCandidateID = candidate.id
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: selectedCandidateID == candidate.id ? "largecircle.fill.circle" : "circle")
                        Text(Self.valueText(candidate))
                            .font(WorkbenchUIStyle.controlValueFont)
                    }
                }
                .buttonStyle(.plain)
                .workbenchProbed("workbench.ahe.assign.candidate.\(candidate.id)")
            }
        }
    }

    private var definitionBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Result Definition").font(WorkbenchUIStyle.controlLabelFont)
            if context?.definitions.isEmpty ?? true {
                Text("Create a Result Definition first in Library → Result Definitions.")
                    .font(WorkbenchUIStyle.controlHintFont)
                    .workbenchProbed("workbench.ahe.assign.noDefinitions")
            } else {
                Picker("Result Definition", selection: $selectedDefinitionID) {
                    Text("Choose…").tag(String?.none)
                    ForEach(context?.definitions ?? []) { definition in
                        Text(definition.displayLabel).tag(String?.some(definition.definitionID))
                    }
                }
                .labelsHidden()
                .workbenchProbed("workbench.ahe.assign.definition")
            }
        }
    }

    @ViewBuilder
    private var previewBlock: some View {
        if let definition = selectedDefinition {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                labeledRow("Target", "\(definition.name)\(definition.qualifier.isEmpty ? "" : " @ \(definition.qualifier)")")
                labeledRow("Current value", currentOnDisk.map(Self.format) ?? "—")
                if let candidate = selectedCandidate, let outcome = conversion {
                    switch outcome {
                    case let .identical(value):
                        labeledRow("Will write", "\(Self.format(value)) \(definition.unit)")
                    case let .converted(value, note):
                        labeledRow("Will write",
                                   "\(Self.format(candidate.value)) \(candidate.unit) → \(Self.format(value)) \(definition.unit) (\(note))")
                    case let .rejected(reason):
                        Text(reason)
                            .font(WorkbenchUIStyle.controlValueFont)
                            .foregroundStyle(WorkbenchUIStyle.errorColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .workbenchProbed("workbench.ahe.assign.rejected")
                    }
                    if let value = outcome.writableValue {
                        Text("\(currentOnDisk.map(Self.format) ?? "—") → \(Self.format(value))")
                            .font(WorkbenchUIStyle.controlValueFont.monospacedDigit())
                            .workbenchProbed("workbench.ahe.assign.oldToNew")
                    }
                } else if selectedCandidate == nil {
                    Text("Choose which value to write.")
                        .font(WorkbenchUIStyle.controlHintFont)
                }
            }
        }
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(label).font(WorkbenchUIStyle.controlLabelFont)
            Text(value)
                .font(WorkbenchUIStyle.controlValueFont)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func prepare() {
        errorMessage = nil
        guard !candidates.isEmpty else {
            loadError = "Nothing to assign."
            return
        }
        guard let resolved = appState.libraryResultContext() else {
            loadError = "Library Root is not set."
            return
        }
        guard let session = LibraryWriteLease.shared.sessionID else {
            loadError = "The Library is not open for writing."
            return
        }
        let first = candidates[0]
        do {
            let sample = try resolved.service.resolveV1AssignmentTarget(
                batchID: first.sourceBatchID, sampleKey: first.sourceSampleKey, rootURL: resolved.rootURL)
            switch resolved.service.loadCatalog(rootURL: resolved.rootURL) {
            case .missing:
                context = Context(service: resolved.service, rootURL: resolved.rootURL, sample: sample,
                                  definitions: [], leaseSessionID: session)
            case let .ok(catalog):
                context = Context(service: resolved.service, rootURL: resolved.rootURL, sample: sample,
                                  definitions: catalog.definitions, leaseSessionID: session)
            case let .unreadable(reason):
                loadError = "Result Definitions file is unreadable; assignment is disabled: \(reason)"
            }
        } catch {
            loadError = error.localizedDescription
        }
        // A single computed value is not a choice; with a correction present the user must pick.
        if candidates.count == 1 { selectedCandidateID = candidates[0].id }
    }

    private func refreshCurrentValue() {
        errorMessage = nil
        guard let context, let definition = selectedDefinition else { currentOnDisk = nil; return }
        do {
            currentOnDisk = try context.service.currentValueOnDisk(
                sample: context.sample, definitionID: definition.definitionID, rootURL: context.rootURL)
        } catch {
            currentOnDisk = nil
            errorMessage = error.localizedDescription
        }
    }

    private func confirm() {
        guard canConfirm, let context,
              let definition = selectedDefinition, let value = conversion?.writableValue else { return }
        errorMessage = nil
        // One attempt per confirmation: a second click can never write again (and `expectedCurrent` would also refuse it).
        didWrite = true
        do {
            try context.service.setValue(
                sample: context.sample,
                definitionID: definition.definitionID,
                newValue: value,
                expectedCurrent: currentOnDisk,
                rootURL: context.rootURL,
                writeGuard: ResultWriteGuard(
                    rootURL: context.rootURL,
                    leaseSessionID: context.leaseSessionID,
                    definition: definition,
                    targetBatchID: context.sample.batchId))
            appState.refreshLibraryAfterResultChange()
            store.noteResultAssigned(metric: metric, definitionLabel: definition.displayLabel, value: value)
            onClose()
        } catch {
            didWrite = false
            errorMessage = error.localizedDescription
            appState.refreshLibraryAfterResultChange()
            refreshCurrentValue()
        }
    }

    // MARK: - Formatting

    static func conditionsText(_ conditions: [String: String]) -> String {
        guard !conditions.isEmpty else { return "Unknown" }
        return conditions.keys.sorted().map { "\($0): \(conditions[$0] ?? "")" }.joined(separator: ", ")
    }

    static func valueText(_ candidate: SampleResultCandidate) -> String {
        switch candidate.origin {
        case .computed:
            return "Computed: \(format(candidate.value)) \(candidate.unit)"
        case let .manualOverride(reason):
            return "Manual correction: \(format(candidate.value)) \(candidate.unit) (\(reason))"
        }
    }

    static func format(_ value: Double) -> String {
        String(format: "%.10g", value)
    }
}
