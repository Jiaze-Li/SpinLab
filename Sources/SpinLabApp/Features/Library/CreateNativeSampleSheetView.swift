import SwiftUI

/// Sheet view providing native Sample creation in the desktop Library.
/// Allows selecting an existing Batch or creating a new Batch, specifying
/// a structured substrate (treatment, material, orientation), and an optional display name.
struct CreateNativeSampleSheetView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isPresented: Bool
    var initialBatchId: String? = nil

    @State private var batchMode: BatchMode = .existing
    @State private var selectedExistingBatchId: String = ""
    @State private var newBatchId: String = ""
    @State private var treatmentChoice: String = ""
    @State private var treatmentOther: String = ""
    @State private var materialChoice: String = ""
    @State private var materialOther: String = ""
    @State private var orientationChoice: String = ""
    @State private var orientationOther: String = ""
    private let substrateChoices = NativeSampleSubstrateChoices.current()
    private static let otherTag = "__other__"
    @State private var customDisplayName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    /// Fixed when the form opens so a repeated submit returns the same sample instead of creating another.
    @State private var pendingSampleUID: String = NativeSampleCreationService.makeSampleUID()

    enum BatchMode: String, CaseIterable, Identifiable {
        case existing = "Existing Batch"
        case new = "New Batch"

        var id: String { rawValue }
    }

    private var existingBatchIds: [String] {
        let batches = appState.library.libraryExistingGroups.values.flatMap { $0 }.map(\.batchId)
        return Array(Set(batches)).sorted { LibrarySort.compareBatch($0, $1) }
    }

    private var effectiveBatchId: String {
        switch batchMode {
        case .existing:
            return selectedExistingBatchId.trimmingCharacters(in: .whitespacesAndNewlines)
        case .new:
            return newBatchId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func resolved(_ choice: String, other: String) -> String {
        choice == Self.otherTag ? other : choice
    }

    /// Composed substrate text, or nil until material and orientation are both given.
    private var substrateDescription: String? {
        substrateChoices.composeDescription(
            material: resolved(materialChoice, other: materialOther),
            orientation: resolved(orientationChoice, other: orientationOther),
            treatment: resolved(treatmentChoice, other: treatmentOther)
        )
    }

    private var defaultDisplayName: String {
        let bId = effectiveBatchId.isEmpty ? "BATCH" : effectiveBatchId
        return "\(bId) - \(substrateDescription ?? "Sample")"
    }

    private var isCreateDisabled: Bool {
        effectiveBatchId.isEmpty ||
        substrateDescription == nil ||
        isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Sample")
                    .font(AppFontScale.groupHeader)
                    .accessibilityIdentifier("CreateSampleSheet.Title")
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("CreateSampleSheet.CloseButton")
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.lg)

            Divider()

            // Form content: sized by its content, never a fixed height (specs/04_UI_RULES.md).
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Batch Selection
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Batch")
                        .font(WorkbenchUIStyle.controlLabelFont)

                    if !existingBatchIds.isEmpty {
                        Picker("Batch Mode", selection: $batchMode) {
                            ForEach(BatchMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("CreateSampleSheet.BatchModePicker")
                    }

                    if batchMode == .existing && !existingBatchIds.isEmpty {
                        Picker("Select Batch", selection: $selectedExistingBatchId) {
                            ForEach(existingBatchIds, id: \.self) { bId in
                                Text(bId).tag(bId)
                            }
                        }
                        .accessibilityIdentifier("CreateSampleSheet.ExistingBatchPicker")
                    } else {
                        TextField("e.g. PN110, SL05", text: $newBatchId)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("CreateSampleSheet.NewBatchTextField")
                    }
                }

                // Substrate: treatment (optional), material, orientation.
                // A Grid keeps the label column as wide as the widest label.
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Substrate")
                        .font(WorkbenchUIStyle.controlLabelFont)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
                        substrateRow(
                            title: "Treatment",
                            options: substrateChoices.treatments,
                            choice: $treatmentChoice, other: $treatmentOther,
                            placeholder: "Default: \(substrateChoices.defaultTreatment)",
                            representedByPlaceholder: substrateChoices.defaultTreatment,
                            idPrefix: "CreateSampleSheet.Treatment")
                        substrateRow(
                            title: "Material *",
                            options: substrateChoices.materials,
                            choice: $materialChoice, other: $materialOther,
                            placeholder: "Select material",
                            idPrefix: "CreateSampleSheet.Material")
                        substrateRow(
                            title: "Orientation *",
                            options: substrateChoices.orientations,
                            choice: $orientationChoice, other: $orientationOther,
                            placeholder: "Select orientation",
                            idPrefix: "CreateSampleSheet.Orientation")
                    }
                    Text("Options come from the Rules Book. Untreated is recorded as \(substrateChoices.defaultTreatment).")
                        .font(WorkbenchUIStyle.controlHintFont)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Display Name (Optional)
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Display Name (Optional)")
                        .font(WorkbenchUIStyle.controlLabelFont)
                    TextField(defaultDisplayName, text: $customDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("CreateSampleSheet.DisplayNameTextField")
                    Text("Leave empty to use readable default: \(defaultDisplayName)")
                        .font(WorkbenchUIStyle.controlHintFont)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Error banner if any
                if let error = errorMessage {
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(WorkbenchUIStyle.errorColor)
                        Text(error)
                            .font(WorkbenchUIStyle.controlValueFont)
                            .foregroundStyle(WorkbenchUIStyle.errorColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(AppSpacing.lg)
                    .background(WorkbenchUIStyle.errorColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("CreateSampleSheet.ErrorMessage")
                }
            }
            .padding(AppSpacing.xxl)

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("CreateSampleSheet.CancelButton")

                Spacer()

                Button("Create Sample") {
                    createSample()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreateDisabled)
                .accessibilityIdentifier("CreateSampleSheet.SubmitButton")
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.lg)
        }
        .frame(minWidth: 460)
        .onAppear {
            setupInitialState()
        }
    }

    private func setupInitialState() {
        if let initial = initialBatchId, !initial.isEmpty {
            if existingBatchIds.contains(initial) {
                batchMode = .existing
                selectedExistingBatchId = initial
            } else {
                batchMode = .new
                newBatchId = initial
            }
        } else if let first = existingBatchIds.first {
            batchMode = .existing
            selectedExistingBatchId = first
        } else {
            batchMode = .new
        }
    }

    @ViewBuilder
    private func substrateRow(
        title: String,
        options: [String],
        choice: Binding<String>,
        other: Binding<String>,
        placeholder: String,
        representedByPlaceholder: String? = nil,
        idPrefix: String
    ) -> some View {
        GridRow {
            Text(title)
                .font(WorkbenchUIStyle.controlLabelFont)
                .gridColumnAlignment(.leading)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                Picker("", selection: choice) {
                    Text(placeholder).tag("")
                    ForEach(options.filter { $0 != representedByPlaceholder }, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Other…").tag(Self.otherTag)
                }
                .labelsHidden()
                .accessibilityIdentifier("\(idPrefix)Picker")
                if choice.wrappedValue == Self.otherTag {
                    TextField("Type value", text: other)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("\(idPrefix)OtherTextField")
                }
            }
        }
    }

    private func createSample() {
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let draft = CreateNativeSampleDraft(
            batchId: effectiveBatchId,
            substrateDescription: substrateDescription ?? "",
            displayName: customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customDisplayName,
            metadata: [:],
            sampleUID: pendingSampleUID,
            numericTags: [:],
            numericDisplay: [:]
        )

        let outcome = appState.createNativeSample(draft: draft)
        switch outcome {
        case .success:
            isPresented = false
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }
}
