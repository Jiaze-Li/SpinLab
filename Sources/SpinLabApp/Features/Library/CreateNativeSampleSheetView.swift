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
    private let labOptions = NewSampleFields.labOptions()
    private let growthMaterialOptions = NewSampleFields.growthMaterialOptions()
    @State private var date: Date = Date()
    @State private var lab: String = ""
    @State private var growthMaterial: String = ""
    /// Number fields are typed as text; empty means "not given".
    @State private var numberTexts: [NumberField: String] = [:]
    @State private var hasAttenuator: Bool = false
    @State private var purpose: String = ""
    @State private var note: String = ""
    @State private var rheedTexts: [RheedField: String] = [:]
    @State private var showsRheed: Bool = false
    @State private var customDisplayName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    /// Fixed when the form opens so a repeated submit returns the same sample instead of creating another.
    @State private var pendingSampleUID: String = NativeSampleCreationService.makeSampleUID()

    enum NumberField: String, CaseIterable, Identifiable {
        case temperature = "Temperature (°C)"
        case pressure = "Pressure (mT)"
        case sampleHeight = "Sample height (mm)"
        case frontEnergy = "Front energy (mJ)"
        case laserVoltage = "Laser voltage (kV)"
        case laserOutputEnergy = "Laser output energy (mJ)"
        case prePulseCount = "Pre-ablation pulses"
        case growthPulseCount = "Growth pulses"
        case frequency = "Frequency (Hz, default 2)"

        var id: String { rawValue }
    }

    enum RheedField: String, CaseIterable, Identifiable {
        case grid = "Grid", focus = "Focus", x1 = "X1", y1 = "Y1", y2 = "Y2", x2 = "X2"
        var id: String { rawValue }
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
        growthMaterial.isEmpty ||
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
                        ForEach(NumberField.allCases) { field in
                            GridRow {
                                Text(field.rawValue).font(WorkbenchUIStyle.controlLabelFont)
                                TextField("", text: numberBinding(field))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("CreateSampleSheet.Number.\(field)")
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
                            ForEach(RheedField.allCases) { field in
                                GridRow {
                                    Text(field.rawValue).font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                                    TextField("", text: rheedBinding(field))
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("CreateSampleSheet.Rheed.\(field)")
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

    private func numberBinding(_ field: NumberField) -> Binding<String> {
        Binding(get: { numberTexts[field] ?? "" }, set: { numberTexts[field] = $0 })
    }

    private func rheedBinding(_ field: RheedField) -> Binding<String> {
        Binding(get: { rheedTexts[field] ?? "" }, set: { rheedTexts[field] = $0 })
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
        func number(_ field: NumberField) throws -> Double? { try parsedNumber(numberTexts[field], label: field.rawValue) }
        func rheed(_ field: RheedField) throws -> Double? { try parsedNumber(rheedTexts[field], label: "RHEED \(field.rawValue)") }
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var fields = NewSampleFields()
        fields.date = dateFormatter.string(from: date)
        fields.lab = lab
        fields.growthMaterial = growthMaterial
        fields.batch = effectiveBatchId
        fields.substrateTreatment = resolved(treatmentChoice, other: treatmentOther)
        fields.substrateMaterial = resolved(materialChoice, other: materialOther)
        fields.substrateOrientation = resolved(orientationChoice, other: orientationOther)
        fields.temperature = try number(.temperature)
        fields.pressure = try number(.pressure)
        fields.sampleHeight = try number(.sampleHeight)
        fields.frontEnergy = try number(.frontEnergy)
        fields.laserVoltage = try number(.laserVoltage)
        fields.laserOutputEnergy = try number(.laserOutputEnergy)
        fields.hasAttenuator = hasAttenuator
        fields.prePulseCount = try number(.prePulseCount)
        fields.growthPulseCount = try number(.growthPulseCount)
        fields.frequency = try number(.frequency)
        fields.purpose = purpose
        fields.note = note
        fields.rheed = NewSampleFields.Rheed(
            grid: try rheed(.grid), focus: try rheed(.focus), x1: try rheed(.x1),
            y1: try rheed(.y1), y2: try rheed(.y2), x2: try rheed(.x2)
        )
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
        let draft: CreateNativeSampleDraft
        switch fields.makeDraft(
            sampleUID: pendingSampleUID,
            choices: substrateChoices,
            displayName: customName.isEmpty ? nil : customName
        ) {
        case let .success(made): draft = made
        case let .failure(error):
            errorMessage = error.localizedDescription
            return
        }
        isSaving = true
        defer { isSaving = false }

        let outcome = appState.createNativeSample(draft: draft)
        switch outcome {
        case .success:
            isPresented = false
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }
}
