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
    /// One row per substrate grown in this run; every row becomes its own sample in the batch.
    @State private var substrateRows: [SubstrateRow] = [SubstrateRow()]
    private let substrateChoices = NativeSampleSubstrateChoices.current()
    private static let otherTag = "__other__"
    private let labOptions = NewSampleFields.labOptions()
    private let growthMaterialOptions = NewSampleFields.growthMaterialOptions()
    /// Fields come from the one shared definition, the same one the phone page is drawn from.
    private let schema = NewSampleFormSchema.shared
    @State private var date: Date = Date()
    @State private var lab: String = ""
    @State private var growthMaterial: String = ""
    /// Number fields are typed as text; empty means "not given".
    @State private var numberTexts: [String: String] = [:]
    @State private var hasAttenuator: Bool = false
    @State private var purpose: String = ""
    @State private var note: String = ""
    @State private var rheedTexts: [String: String] = [:]
    @State private var showsRheed: Bool = false
    @State private var customDisplayName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    /// Fixed when the form opens so a repeated submit returns the same sample instead of creating another.
    @State private var pendingSampleUID: String = NativeSampleCreationService.makeSampleUID()

    struct SubstrateRow: Identifiable, Equatable {
        let id = UUID()
        var treatmentChoice = ""
        var treatmentOther = ""
        var materialChoice = ""
        var materialOther = ""
        var orientationChoice = ""
        var orientationOther = ""
    }

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

    private func resolvedSubstrate(_ row: SubstrateRow) -> NewSampleFields.Substrate {
        NewSampleFields.Substrate(
            treatment: resolved(row.treatmentChoice, other: row.treatmentOther),
            material: resolved(row.materialChoice, other: row.materialOther),
            orientation: resolved(row.orientationChoice, other: row.orientationOther)
        )
    }

    /// Composed text of the first substrate, or nil until its material and orientation are given.
    private var substrateDescription: String? {
        let first = resolvedSubstrate(substrateRows[0])
        return substrateChoices.composeDescription(
            material: first.material, orientation: first.orientation, treatment: first.treatment
        )
    }

    private var defaultDisplayName: String {
        let bId = effectiveBatchId.isEmpty ? "BATCH" : effectiveBatchId
        return "\(bId) - \(substrateDescription ?? "Sample")"
    }

    /// An added row must be fully filled (material and orientation) or left blank.
    private var hasHalfFilledExtraRow: Bool {
        substrateRows.dropFirst().contains { row in
            let substrate = resolvedSubstrate(row)
            return !substrate.isEmpty && substrateChoices.composeDescription(
                material: substrate.material, orientation: substrate.orientation, treatment: substrate.treatment
            ) == nil
        }
    }

    private var isCreateDisabled: Bool {
        effectiveBatchId.isEmpty ||
        growthMaterial.isEmpty ||
        substrateDescription == nil ||
        hasHalfFilledExtraRow ||
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

                // Substrates: one row each (treatment, material, orientation); every row is its own sample.
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Substrate")
                        .font(WorkbenchUIStyle.controlLabelFont)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppSpacing.md, verticalSpacing: AppSpacing.md) {
                        GridRow {
                            Text("Treatment").font(WorkbenchUIStyle.controlHintFont).gridColumnAlignment(.leading)
                            Text("Material *").font(WorkbenchUIStyle.controlHintFont).gridColumnAlignment(.leading)
                            Text("Orientation *").font(WorkbenchUIStyle.controlHintFont).gridColumnAlignment(.leading)
                        }
                        ForEach($substrateRows) { $row in
                            let index = substrateRows.firstIndex(where: { $0.id == row.id }) ?? 0
                            let suffix = index == 0 ? "" : ".\(index + 1)"
                            GridRow {
                                substratePicker(
                                    options: substrateChoices.treatments,
                                    choice: $row.treatmentChoice, other: $row.treatmentOther,
                                    placeholder: "Default: \(substrateChoices.defaultTreatment)",
                                    representedByPlaceholder: substrateChoices.defaultTreatment,
                                    idPrefix: "CreateSampleSheet.Treatment\(suffix)")
                                substratePicker(
                                    options: substrateChoices.materials,
                                    choice: $row.materialChoice, other: $row.materialOther,
                                    placeholder: "Select",
                                    idPrefix: "CreateSampleSheet.Material\(suffix)")
                                substratePicker(
                                    options: substrateChoices.orientations,
                                    choice: $row.orientationChoice, other: $row.orientationOther,
                                    placeholder: "Select",
                                    idPrefix: "CreateSampleSheet.Orientation\(suffix)")
                                if index != 0 {
                                    Button {
                                        substrateRows.removeAll { $0.id == row.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this substrate")
                                    .accessibilityIdentifier("CreateSampleSheet.RemoveSubstrate\(suffix)")
                                }
                            }
                        }
                    }
                    Button {
                        substrateRows.append(SubstrateRow())
                    } label: {
                        Label("Add substrate", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("CreateSampleSheet.AddSubstrateButton")
                    Text("Options come from the Rules Book. Untreated is recorded as \(substrateChoices.defaultTreatment). Each substrate becomes its own sample in this batch, sharing the growth record below.")
                        .font(WorkbenchUIStyle.controlHintFont)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Growth record: the same fields as the Obsidian deposition template.
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Growth Record (Optional)")
                        .font(WorkbenchUIStyle.controlLabelFont)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
                        GridRow {
                            Text("Date").font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .accessibilityIdentifier("CreateSampleSheet.DatePicker")
                        }
                        GridRow {
                            Text("Lab").font(WorkbenchUIStyle.controlLabelFont)
                            Picker("", selection: $lab) {
                                Text("None").tag("")
                                ForEach(labOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("CreateSampleSheet.LabPicker")
                        }
                        GridRow {
                            Text("Material *").font(WorkbenchUIStyle.controlLabelFont)
                            Picker("", selection: $growthMaterial) {
                                Text("Select material").tag("")
                                ForEach(growthMaterialOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("CreateSampleSheet.GrowthMaterialPicker")
                        }
                        ForEach(schema.numberFields) { field in
                            GridRow {
                                Text(field.displayLabel).font(WorkbenchUIStyle.controlLabelFont)
                                TextField(field.placeholder.map { "Default \($0)" } ?? "", text: numberBinding(field.key))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("CreateSampleSheet.Number.\(field.key)")
                            }
                        }
                        GridRow {
                            Text("Attenuator").font(WorkbenchUIStyle.controlLabelFont)
                            Toggle("In the beam path", isOn: $hasAttenuator)
                                .accessibilityIdentifier("CreateSampleSheet.AttenuatorToggle")
                        }
                        GridRow {
                            Text("Purpose").font(WorkbenchUIStyle.controlLabelFont)
                            TextField("", text: $purpose)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("CreateSampleSheet.PurposeTextField")
                        }
                        GridRow {
                            Text("Note").font(WorkbenchUIStyle.controlLabelFont)
                            TextField("", text: $note)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("CreateSampleSheet.NoteTextField")
                        }
                    }
                    DisclosureGroup("RHEED", isExpanded: $showsRheed) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
                            ForEach(schema.rheedFields) { field in
                                GridRow {
                                    Text(field.label).font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                                    TextField("", text: rheedBinding(field.key))
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("CreateSampleSheet.Rheed.\(field.key)")
                                }
                            }
                        }
                    }
                    Text("Units are added automatically, the same as when importing from the Registry.")
                        .font(WorkbenchUIStyle.controlHintFont)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Display Name (Optional)
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Display Name (Optional)")
                        .font(WorkbenchUIStyle.controlLabelFont)
                    TextField(defaultDisplayName, text: $customDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(substrateRows.count > 1)
                        .accessibilityIdentifier("CreateSampleSheet.DisplayNameTextField")
                    Text(substrateRows.count > 1
                         ? "With several substrates each sample is named from its batch and substrate."
                         : "Leave empty to use readable default: \(defaultDisplayName)")
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
    private func substratePicker(
        options: [String],
        choice: Binding<String>,
        other: Binding<String>,
        placeholder: String,
        representedByPlaceholder: String? = nil,
        idPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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

    private func numberBinding(_ key: String) -> Binding<String> {
        Binding(get: { numberTexts[key] ?? "" }, set: { numberTexts[key] = $0 })
    }

    private func rheedBinding(_ key: String) -> Binding<String> {
        Binding(get: { rheedTexts[key] ?? "" }, set: { rheedTexts[key] = $0 })
    }

    /// Empty -> nil (not given). Anything that is not a plain number is an error naming the field.
    private func parsedNumber(_ text: String?, label: String) throws -> Double? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed) else { throw FieldError(message: "\(label) needs a number, for example 250.") }
        return value
    }

    private struct FieldError: Error { let message: String }

    private func collectFields() throws -> NewSampleFields {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var fields = NewSampleFields()
        fields.date = dateFormatter.string(from: date)
        fields.lab = lab
        fields.growthMaterial = growthMaterial
        fields.batch = effectiveBatchId
        let first = resolvedSubstrate(substrateRows[0])
        fields.substrateTreatment = first.treatment
        fields.substrateMaterial = first.material
        fields.substrateOrientation = first.orientation
        fields.extraSubstrates = substrateRows.dropFirst().map(resolvedSubstrate)
        for field in schema.numberFields {
            fields.setNumber(try parsedNumber(numberTexts[field.key], label: field.displayLabel), forKey: field.key)
        }
        fields.hasAttenuator = hasAttenuator
        fields.purpose = purpose
        fields.note = note
        for field in schema.rheedFields {
            fields.setRheed(try parsedNumber(rheedTexts[field.key], label: "RHEED \(field.label)"), forKey: field.key)
        }
        return fields
    }

    private func createSample() {
        guard !isSaving else { return }
        errorMessage = nil

        let fields: NewSampleFields
        do {
            fields = try collectFields()
        } catch let error as FieldError {
            errorMessage = error.message
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let customName = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let drafts: [CreateNativeSampleDraft]
        switch fields.makeDrafts(
            sampleUID: pendingSampleUID,
            choices: substrateChoices,
            displayName: customName.isEmpty ? nil : customName
        ) {
        case let .success(made): drafts = made
        case let .failure(error):
            errorMessage = error.localizedDescription
            return
        }
        isSaving = true
        defer { isSaving = false }

        // Stop at the first failure; pressing Create again finds the ones already saved (same ids) and makes the rest.
        for draft in drafts {
            if case let .failure(error) = appState.createNativeSample(draft: draft) {
                errorMessage = error.localizedDescription
                return
            }
        }
        isPresented = false
    }
}
