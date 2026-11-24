import SwiftUI

/// Sheet for editing a Batch's shared growth parameters (single authority on `batch.json`).
struct EditBatchGrowthSheetView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isPresented: Bool
    let batch: LibraryBatch

    private let schema = NewSampleFormSchema.shared
    private let labOptions = NewSampleFields.labOptions()
    private let growthMaterialOptions = NewSampleFields.growthMaterialOptions()

    @State private var dateText: String = ""
    @State private var lab: String = ""
    @State private var growthMaterial: String = ""
    @State private var numberTexts: [String: String] = [:]
    @State private var hasAttenuator: Bool = false
    @State private var rheedTexts: [String: String] = [:]
    @State private var showsRheed: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @State private var contentHeight: CGFloat = 0

    private static let pairsPerLine = 3
    private static let controlColumnWidth: CGFloat = 120

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

    private func pairedGrid(_ cells: [FieldCell]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
            ForEach(Array(stride(from: 0, to: cells.count, by: Self.pairsPerLine)), id: \.self) { start in
                GridRow {
                    ForEach(0..<Self.pairsPerLine, id: \.self) { offset in
                        let i = start + offset
                        if i < cells.count {
                            Text(cells[i].label)
                                .font(WorkbenchUIStyle.controlLabelFont)
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
                TextField("yyyy-MM-dd", text: $dateText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                    .accessibilityIdentifier("EditBatchSheet.DateTextField"))),
            FieldCell(id: "lab", label: "Lab", control: AnyView(
                Picker("", selection: $lab) {
                    Text("None").tag("")
                    ForEach(labOptions, id: \.self) { Text($0).tag($0) }
                    if !lab.isEmpty && !labOptions.contains(lab) {
                        Text(lab).tag(lab)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .frame(minWidth: Self.controlColumnWidth, alignment: .leading)
                .accessibilityIdentifier("EditBatchSheet.LabPicker"))),
            FieldCell(id: "material", label: "Material", control: AnyView(
                Picker("", selection: $growthMaterial) {
                    Text("Select material").tag("")
                    ForEach(growthMaterialOptions, id: \.self) { Text($0).tag($0) }
                    if !growthMaterial.isEmpty && !growthMaterialOptions.contains(growthMaterial) {
                        Text(growthMaterial).tag(growthMaterial)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .frame(minWidth: Self.controlColumnWidth, alignment: .leading)
                .accessibilityIdentifier("EditBatchSheet.GrowthMaterialPicker")))
        ]
        for field in schema.numberFields {
            cells.append(FieldCell(id: field.key, label: field.displayLabel, control: AnyView(
                TextField(field.placeholder.map { "Default \($0)" } ?? "", text: numberBinding(field.key))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                    .accessibilityIdentifier("EditBatchSheet.Number.\(field.key)"))))
        }
        cells.append(FieldCell(id: "attenuator", label: "Attenuator", control: AnyView(
            Toggle("In the beam path", isOn: $hasAttenuator)
                .accessibilityIdentifier("EditBatchSheet.AttenuatorToggle"))))
        return cells
    }

    private var rheedCells: [FieldCell] {
        schema.rheedFields.map { field in
            FieldCell(id: field.key, label: field.label, control: AnyView(
                TextField("", text: rheedBinding(field.key))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlColumnWidth)
                    .accessibilityIdentifier("EditBatchSheet.Rheed.\(field.key)")))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Batch · \(batch.id)")
                    .font(AppFontScale.groupHeader)
                    .accessibilityIdentifier("EditBatchSheet.Title")
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
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
                        Text("Growth Parameters")
                            .font(AppFontScale.groupHeader)
                    }

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

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Batch") {
                    saveBatch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .accessibilityIdentifier("EditBatchSheet.SaveButton")
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.lg)
        }
        .frame(minWidth: 920)
        .onAppear { loadFromBatch() }
    }

    private func numberBinding(_ key: String) -> Binding<String> {
        Binding(get: { numberTexts[key] ?? "" }, set: { numberTexts[key] = $0 })
    }

    private func rheedBinding(_ key: String) -> Binding<String> {
        Binding(get: { rheedTexts[key] ?? "" }, set: { rheedTexts[key] = $0 })
    }

    private func loadFromBatch() {
        dateText = batch.metadata["date"] ?? batch.metadata[LibraryBatch.legacyDateMetadataKey] ?? ""
        lab = batch.metadata["lab"] ?? ""
        growthMaterial = batch.metadata["material"] ?? batch.metadata[LibraryBatch.legacyMaterialMetadataKey] ?? ""
        hasAttenuator = batch.metadata["attenuator"] == "yes"
        for field in schema.numberFields {
            if let num = batch.numericTags[field.tag] {
                numberTexts[field.key] = num.rounded() == num ? String(Int(num)) : String(num)
            }
        }
        for field in schema.rheedFields {
            if let val = batch.metadata[field.metadataKey], !val.isEmpty {
                rheedTexts[field.key] = val
                showsRheed = true
            }
        }
    }

    private func saveBatch() {
        guard !isSaving else { return }
        errorMessage = nil

        var updated = batch
        func setMeta(_ key: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                updated.metadata.removeValue(forKey: key)
            } else {
                updated.metadata[key] = trimmed
            }
        }
        setMeta("date", dateText)
        setMeta("lab", lab)
        setMeta("material", growthMaterial)
        if hasAttenuator {
            updated.metadata["attenuator"] = "yes"
        } else {
            updated.metadata.removeValue(forKey: "attenuator")
        }

        for field in schema.numberFields {
            let raw = (numberTexts[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                updated.numericTags.removeValue(forKey: field.tag)
                updated.numericDisplay.removeValue(forKey: field.tag)
            } else if let num = Double(raw) {
                updated.numericTags[field.tag] = num
                updated.numericDisplay[field.tag] = LibraryRegistryParser.numericDisplay(canonicalKey: field.tag, number: num)
            } else {
                errorMessage = "\(field.displayLabel) needs a number."
                return
            }
        }

        for field in schema.rheedFields {
            let raw = (rheedTexts[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                updated.metadata.removeValue(forKey: field.metadataKey)
            } else if let num = Double(raw) {
                updated.metadata[field.metadataKey] = num.rounded() == num ? String(Int(num)) : String(num)
            } else {
                errorMessage = "RHEED \(field.label) needs a number."
                return
            }
        }

        updated.updatedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        isSaving = true
        defer { isSaving = false }

        if appState.saveBatchGrowthEdits(updated) {
            isPresented = false
        } else {
            errorMessage = appState.library.libraryDrawerError ?? "Failed to save batch."
        }
    }
}
