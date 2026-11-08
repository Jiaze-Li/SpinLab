import SwiftUI

/// Sheet view providing native Sample creation in the desktop Library.
/// Allows selecting an existing Batch or creating a new Batch, specifying
/// distinguishing substrate identity, optional substrate description, and optional display name.
struct CreateNativeSampleSheetView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isPresented: Bool
    var initialBatchId: String? = nil

    @State private var batchMode: BatchMode = .existing
    @State private var selectedExistingBatchId: String = ""
    @State private var newBatchId: String = ""
    @State private var substrateIdentity: String = ""
    @State private var substrateDescription: String = ""
    @State private var customDisplayName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false

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

    private var defaultDisplayName: String {
        let bId = effectiveBatchId.isEmpty ? "BATCH" : effectiveBatchId
        let sId = substrateIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        let sDesc = substrateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sDesc.isEmpty && sDesc != sId {
            return "\(bId) - \(sDesc) (\(sId.isEmpty ? "Sample" : sId))"
        } else if !sId.isEmpty {
            return "\(bId) - \(sId)"
        } else {
            return "\(bId) - Sample"
        }
    }

    private var isCreateDisabled: Bool {
        effectiveBatchId.isEmpty ||
        substrateIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Sample")
                    .font(.headline)
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
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // Form Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Batch Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Batch")
                            .font(.subheadline.weight(.semibold))

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

                    // Substrate Identity (Distinguishing Key)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Substrate Identity *")
                            .font(.subheadline.weight(.semibold))
                        TextField("e.g. S1, Piece-A, 110-1", text: $substrateIdentity)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("CreateSampleSheet.SubstrateIdentityTextField")
                        Text("Distinguishes the physical substrate/sample within this batch. Decoupled from display name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Substrate Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Substrate Description")
                            .font(.subheadline.weight(.semibold))
                        TextField("e.g. STO(001), LAO(110) annealed", text: $substrateDescription)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("CreateSampleSheet.SubstrateDescriptionTextField")
                        Text("Known materials/orientations will be formatted; unknown properties will not be guessed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Display Name (Optional)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display Name (Optional)")
                            .font(.subheadline.weight(.semibold))
                        TextField(defaultDisplayName, text: $customDisplayName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("CreateSampleSheet.DisplayNameTextField")
                        Text("Leave empty to use readable default: \(defaultDisplayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Error banner if any
                    if let error = errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("CreateSampleSheet.ErrorMessage")
                    }
                }
                .padding(20)
            }

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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 480)
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

    private func createSample() {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let draft = CreateNativeSampleDraft(
            batchId: effectiveBatchId,
            substrateIdentity: substrateIdentity,
            substrateDescription: substrateDescription,
            displayName: customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customDisplayName,
            metadata: [:],
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
