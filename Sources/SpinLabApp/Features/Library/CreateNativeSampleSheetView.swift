import SwiftUI

/// Sheet view providing native Sample creation in the desktop Library.
/// Allows selecting an existing Batch or creating a new Batch, specifying
/// and a structured substrate (treatment, material, orientation) per sample.
struct CreateNativeSampleSheetView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isPresented: Bool
    var initialBatchId: String? = nil

    /// Full batch id typed when the prefix is "Other".
    @State private var newBatchId: String = ""
    @State private var newBatchPrefix: String = ""
    @State private var newBatchNumber: String = ""
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

    private var existingBatchIds: [String] {
        let batches = appState.library.libraryExistingGroups.values.flatMap { $0 }.map(\.batchId)
        return Array(Set(batches)).sorted { LibrarySort.compareBatch($0, $1) }
    }

    private var effectiveBatchId: String {
        if newBatchPrefix == NewBatchId.other || newBatchPrefix.isEmpty {
            return newBatchId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return NewBatchId.compose(prefix: newBatchPrefix, number: newBatchNumber)
    }

    /// Says whether the typed batch is already in the Library, so a typo shows before it makes a new batch.
    private var batchHint: String? {
        let id = effectiveBatchId
        guard !id.isEmpty, !newBatchNumberIsInvalid else { return nil }
        return existingBatchIds.contains(id) ? "Existing batch" : "New batch"
    }

    /// The prefixes the Rules Book lists (sample identification, "starts with").
    private var batchPrefixes: [String] { BatchPrefixes.current() }

    /// A prefix is picked but the number after it is not digits yet.
    private var newBatchNumberIsInvalid: Bool {
        !newBatchPrefix.isEmpty && newBatchPrefix != NewBatchId.other
            && !newBatchNumber.isEmpty && !NewBatchId.isValidNumber(newBatchNumber)
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
        newBatchNumberIsInvalid ||
        growthMaterial.isEmpty ||
        substrateDescription == nil ||
        hasHalfFilledExtraRow ||
        isSaving
    }

    @State private var contentHeight: CGFloat = 0

    /// Room left for the form after the pinned title bar, action bar and a margin to the screen edges.
    private var maxFormHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(screen - AppSpacing.xxl * 8, AppSpacing.xxl * 10)
    }

    private struct SheetContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private struct FieldCell: Identifiable {
        let id: String
        let label: String
        let control: AnyView
    }

    /// Three label+control pairs per line so a wide window is not one field per row (identical column edges, VC-9).
    private static let pairsPerLine = 3
    /// Width of every control column in the growth grid; menus never go below their widest option.
    private static let controlColumnWidth: CGFloat = 120

    private func pairedGrid(_ cells: [FieldCell]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
            ForEach(Array(stride(from: 0, to: cells.count, by: Self.pairsPerLine)), id: \.self) { start in
                GridRow {
                    ForEach(0..<Self.pairsPerLine, id: \.self) { offset in
                        let i = start + offset
                        if i < cells.count {
                            Text(cells[i].label).font(WorkbenchUIStyle.controlLabelFont)
                                .gridColumnAlignment(.leading)
                                .padding(.leading, offset == 0 ? 0 : AppSpacing.lg)
                            cells[i].control
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private var growthCells: [FieldCell] {
        var cells: [FieldCell] = [
            FieldCell(id: "date", label: "Date", control: AnyView(
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                .fixedSize()
                .frame(minWidth: Self.controlColumnWidth, alignment: .leading)
                    .accessibilityIdentifier("CreateSampleSheet.DatePicker"))),
            FieldCell(id: "lab", label: "Lab", control: AnyView(
                Picker("", selection: $lab) {
                    Text("None").tag("")
                    ForEach(labOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .frame(minWidth: Self.controlColumnWidth, alignment: .leading)
                .accessibilityIdentifier("CreateSampleSheet.LabPicker"))),
            FieldCell(id: "material", label: "Material *", control: AnyView(
                Picker("", selection: $growthMaterial) {
                    Text("Select material").tag("")
                    ForEach(growthMaterialOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .frame(minWidth: Self.controlColumnWidth, alignment: .leading)
                .accessibilityIdentifier("CreateSampleSheet.GrowthMaterialPicker")))
        ]
        for field in schema.numberFields {
            cells.append(FieldCell(id: field.key, label: field.displayLabel, control: AnyView(
                TextField(field.placeholder.map { "Default \($0)" } ?? "", text: numberBinding(field.key))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                    .accessibilityIdentifier("CreateSampleSheet.Number.\(field.key)"))))
        }
        cells.append(FieldCell(id: "attenuator", label: "Attenuator", control: AnyView(
            Toggle("In the beam path", isOn: $hasAttenuator)
                .accessibilityIdentifier("CreateSampleSheet.AttenuatorToggle"))))
        cells.append(FieldCell(id: "purpose", label: "Purpose", control: AnyView(
            TextField("", text: $purpose)
                .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                .accessibilityIdentifier("CreateSampleSheet.PurposeTextField"))))
        cells.append(FieldCell(id: "note", label: "Note", control: AnyView(
            TextField("", text: $note)
                .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                .accessibilityIdentifier("CreateSampleSheet.NoteTextField"))))
        return cells
    }

    private var rheedCells: [FieldCell] {
        schema.rheedFields.map { field in
            FieldCell(id: field.key, label: field.label, control: AnyView(
                TextField("", text: rheedBinding(field.key))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                    .accessibilityIdentifier("CreateSampleSheet.Rheed.\(field.key)")))
        }
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

            // Form content: takes its natural height, but never more than the screen allows;
            // only this middle part scrolls, the title and the action buttons stay pinned
            // (specs/04_UI_RULES.md, Sheets and Dialogs).
            ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Batch and substrates share one grid: the batch sits beside the first substrate row;
                // every substrate row is its own sample in that batch.
                GroupBox {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Grid(alignment: .topLeading, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
                            GridRow {
                                Text("Batch *").font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                                Text("Treatment").font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                                Text("Material *").font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                                Text("Orientation *").font(WorkbenchUIStyle.controlLabelFont).gridColumnAlignment(.leading)
                            }
                            ForEach($substrateRows) { $row in
                                let index = substrateRows.firstIndex(where: { $0.id == row.id }) ?? 0
                                let suffix = index == 0 ? "" : ".\(index + 1)"
                                GridRow {
                                    if index == 0 {
                                        batchCell
                                    } else {
                                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                    }
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
                        HStack(spacing: AppSpacing.lg) {
                            Button {
                                substrateRows.append(SubstrateRow())
                            } label: {
                                Label("Add substrate", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("CreateSampleSheet.AddSubstrateButton")
                            if substrateRows.count > 1 {
                                Text("Each substrate becomes its own sample in this batch.")
                                    .font(WorkbenchUIStyle.controlHintFont)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                } label: {
                    Text("Batch & substrate").font(AppFontScale.groupHeader)
                }

                // Growth: the same fields, in the same order, as the phone page.
                GroupBox {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        pairedGrid(growthCells)
                        DisclosureGroup("RHEED", isExpanded: $showsRheed) {
                            pairedGrid(rheedCells)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                } label: {
                    Text("Growth").font(AppFontScale.groupHeader)
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
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
            })
            }
            .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
            .frame(height: min(contentHeight, maxFormHeight))

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
        .frame(minWidth: 920)
        .onAppear {
            setupInitialState()
        }
    }

    /// Prefix + number (or a full id for "Other"), sized to its content, with a short existing/new note under it.
    private var batchCell: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                Picker("Prefix", selection: $newBatchPrefix) {
                    ForEach(batchPrefixes, id: \.self) { Text($0).tag($0) }
                    Text(NewBatchId.other).tag(NewBatchId.other)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("CreateSampleSheet.NewBatchPrefixPicker")
                if newBatchPrefix == NewBatchId.other {
                    TextField("Full id, e.g. 106/SRO1", text: $newBatchId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Self.controlColumnWidth)
                        .accessibilityIdentifier("CreateSampleSheet.NewBatchTextField")
                } else {
                    TextField("Number", text: $newBatchNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Self.controlColumnWidth)
                        .accessibilityIdentifier("CreateSampleSheet.NewBatchNumberField")
                }
            }
            if newBatchNumberIsInvalid {
                Text("Digits only, or choose Other.")
                    .font(WorkbenchUIStyle.controlHintFont)
                    .foregroundStyle(WorkbenchUIStyle.errorColor)
            } else if let hint = batchHint {
                Text(hint)
                    .font(WorkbenchUIStyle.controlHintFont)
                    .accessibilityIdentifier("CreateSampleSheet.BatchHint")
            }
        }
    }

    private func setupInitialState() {
        newBatchPrefix = batchPrefixes.first ?? NewBatchId.other
        let initial = (initialBatchId?.isEmpty == false) ? initialBatchId : existingBatchIds.first
        guard let initial else { return }
        if let parts = NewBatchId.split(initial, prefixes: batchPrefixes) {
            newBatchPrefix = parts.prefix
            newBatchNumber = parts.number
        } else {
            newBatchPrefix = NewBatchId.other
            newBatchId = initial
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
            .fixedSize()
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
        let drafts: [CreateNativeSampleDraft]
        switch fields.makeDrafts(sampleUID: pendingSampleUID, choices: substrateChoices) {
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
