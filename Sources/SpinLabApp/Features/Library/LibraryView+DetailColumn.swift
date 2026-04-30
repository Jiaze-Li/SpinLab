import SwiftUI

extension LibraryView {
    var libraryDetailColumn: some View {
        GeometryReader { proxy in
            let detailWidth = proxy.size.width
            let detailHeight = proxy.size.height
            let sectionWidth = max(detailWidth - 24, 0)
            let sectionSpacing = adaptiveDetailSectionSpacing(for: detailHeight)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    if appState.library.recomputeStaleCount > 0 {
                        RecomputeStaleBannerView(
                            staleCount: appState.library.recomputeStaleCount,
                            onDismiss: { appState.library.dismissRecomputeBanner() },
                            onViewPreview: { appState.library.openRecomputePreview() }
                        )
                    }

                    sampleDetailHeader

                    if let sample = selectedSample {
                        if isEditingSelectedSample, let draft = lib.librarySampleEditDraft {
                            let sections = makeDetailSections(for: sample)
                            let globalFirstColumnWidth = alignedFirstColumnWidth(
                                fields: sections.allFields,
                                availableWidth: sectionWidth
                            )
                            samplePrimarySection(
                                for: sample,
                                draft: draft,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )
                            Divider()
                            editNumericSection(draft: draft)
                            Divider()
                            editMetadataSection(draft: draft, availableWidth: sectionWidth)
                        } else {
                            let sections = makeDetailSections(for: sample)
                            let globalFirstColumnWidth = alignedFirstColumnWidth(
                                fields: sections.allFields,
                                availableWidth: sectionWidth
                            )

                            samplePrimarySection(
                                for: sample,
                                draft: nil,
                                availableWidth: sectionWidth,
                                sharedFirstColumnWidth: globalFirstColumnWidth
                            )

                            if !selectedChangeHighlights(for: sample).isEmpty {
                                Divider()
                                Text("Pending Changes")
                                    .font(.headline)
                                pendingChangesSection(for: sample)
                            }

                            if !sections.numericFields.isEmpty {
                                Divider()
                                Text("Numeric Tags")
                                    .font(sampleDetailSectionTitleFont)
                                detailSection(
                                    fields: sections.numericFields,
                                    availableWidth: sectionWidth,
                                    sharedFirstColumnWidth: globalFirstColumnWidth
                                )
                            }

                            Divider()
                            MeasurementDataSectionView(
                                measurementData: appState.library.measurementData,
                                conditionAliasBook: appState.library.conditionAliasBook,
                                availableWidth: sectionWidth,
                                onDeleteMetric: { identityKey in
                                    appState.library.deleteMetricRecord(identityKey: identityKey)
                                }
                            )

                            Divider()
                            LibraryMeasurementsDoneSection(
                                measurements: sample.appliedMeasurements,
                                measurementSets: sample.measurementSets,
                                workflowDisplayNameByID: workflowDisplayNameByID,
                                workflowConditionOrderByID: workflowConditionOrderByID,
                                onDelete: { m in appState.library.deleteAppliedMeasurement(m) },
                                workbenchResults: appState.library.workbenchResults,
                                measurementPlotIndex: appState.library.measurementPlotIndex,
                                libraryRootURL: appState.library.librarySettings.rootPath.map { URL(fileURLWithPath: $0) },
                                onDeleteChart: { ref in appState.library.deleteWorkbenchResult(ref) },
                                onCreateSet: { name, wf, member in appState.library.createMeasurementSet(name: name, workflow: wf, initialMember: member) },
                                onAddToSet: { setID, fileName in appState.library.addToMeasurementSet(setID: setID, fileName: fileName) },
                                onRemoveFromSet: { setID, fileName in appState.library.removeFromMeasurementSet(setID: setID, fileName: fileName) },
                                onRenameSet: { setID, newName in appState.library.renameMeasurementSet(setID: setID, newName: newName) },
                                onDeleteSet: { setID in appState.library.deleteMeasurementSet(setID: setID) },
                                onShowConditionDetail: { m in conditionDetailMeasurement = m },
                                expandedWorkflows: $expandedWorkflows,
                                expandedSets: $expandedSets,
                                expandedUncategorized: $expandedUncategorized
                            )

                            Divider()
                            DisclosureGroup(isExpanded: $isMetadataSectionExpanded) {
                                if sample.orderedMetadata.isEmpty {
                                    Text("No metadata")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    detailSection(
                                        fields: sections.metadataFields,
                                        availableWidth: sectionWidth,
                                        sharedFirstColumnWidth: globalFirstColumnWidth
                                    )
                                }
                            } label: {
                                Text("Metadata")
                                    .font(sampleDetailSectionTitleFont)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture { isMetadataSectionExpanded.toggle() }
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "No Sample Selected",
                            systemImage: "tray",
                            description: Text("Select a prefix, batch, and sample to view metadata.")
                        )
                    }
                }
                .frame(minHeight: max(detailHeight - 8, 0), alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
            }
        }
        .onChange(of: appState.workbench.aheWorkspace.persistCount) { _, _ in
            appState.library.loadWorkbenchResultsForCurrentSelection()
            appState.library.loadMeasurementDataForCurrentSelection()
        }
    }

    @ViewBuilder
    func samplePrimarySection(
        for sample: LibrarySample,
        draft: LibrarySampleEditDraft?,
        availableWidth: CGFloat,
        sharedFirstColumnWidth: CGFloat?
    ) -> some View {
        if let firstWidth = sharedFirstColumnWidth {
            HStack(alignment: .top, spacing: 12) {
                samplePrimaryLeftColumn(for: sample)
                    .frame(width: firstWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                samplePrimaryRightColumn(for: sample, draft: draft)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                samplePrimaryLeftColumn(for: sample)
                samplePrimaryRightColumn(for: sample, draft: draft)
            }
        }
    }

    @ViewBuilder
    func samplePrimaryLeftColumn(for sample: LibrarySample) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataValueRow(label: "Sample", value: sample.displayName)
            MetadataValueRow(label: "Sample Key", value: sample.id, monospaced: true)
            MetadataValueRow(label: "Substrate", value: sample.substrateDisplay)
        }
    }

    @ViewBuilder
    func samplePrimaryRightColumn(for sample: LibrarySample, draft: LibrarySampleEditDraft?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataValueRow(label: "Batch", value: sample.batchId)
            HStack {
                Button("修改日志") {
                    isShowingSampleChangeLog = true
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if draft != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Substrate Tags")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("comma-separated substrate tags", text: substrateTagsBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            } else if !sample.substrateTags.isEmpty {
                MetadataValueRow(label: "Substrate Tags", value: sample.substrateTags.joined(separator: ", "))
            } else {
                MetadataValueRow(label: "Substrate Tags", value: "None")
            }
        }
    }

    var sampleDetailHeader: some View {
        LibrarySampleDetailHeaderView(
            isEditingSelectedSample: isEditingSelectedSample,
            sampleEditIsDirty: lib.librarySampleEditIsDirty,
            sampleEditIsSaving: lib.librarySampleEditIsSaving,
            canEditSelectedLibrarySample: lib.canEditSelectedLibrarySample,
            sampleEditError: lib.librarySampleEditError,
            sampleEditMessage: lib.librarySampleEditMessage,
            onLoadGlobalManualLogs: {
                appState.library.loadLibraryGlobalManualLogs()
                isShowingGlobalManualLog = true
            },
            onLoadMetadataSyncLogs: {
                appState.library.loadLibraryMetadataSyncLogs()
                isShowingMetadataSyncLog = true
            },
            onCancelEdit: {
                appState.library.cancelEditingSelectedLibrarySample()
            },
            onSaveEdit: {
                appState.library.saveLibrarySampleEdits()
            },
            onBeginEdit: {
                appState.library.beginEditingSelectedDrawerSampleIfNeeded()
            }
        )
    }

    var isEditingSelectedSample: Bool {
        guard let sample = selectedSample,
              let draft = lib.librarySampleEditDraft else {
            return false
        }
        return draft.sampleId == sample.id
    }

    @ViewBuilder
    func editNumericSection(draft: LibrarySampleEditDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Numeric Tags")
                .font(.headline)
            if draft.numericValues.isEmpty {
                Text("No numeric tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.numericValues) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.key)
                            .font(.callout.weight(.semibold))
                            .frame(width: 120, alignment: .leading)
                        TextField(entry.key, text: numericValueBinding(for: entry.key))
                            .textFieldStyle(.roundedBorder)
                        if !entry.unit.isEmpty {
                            Text(entry.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func editMetadataSection(draft: LibrarySampleEditDraft, availableWidth: CGFloat) -> some View {
        let fields: [DetailField] = draft.metadataValues.map { entry in
            DetailField(label: entry.key, value: entry.value, fullWidth: computationService.isLongField(entry.value))
        }
        let rows = computationService.groupedFields(fields)
        let firstColumnWidth = computationService.sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)
            if draft.metadataValues.isEmpty {
                Text("No metadata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.indices), id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    if row.count == 1 {
                        editMetadataFieldRow(row[0], fillWidth: true)
                    } else if let firstColumnWidth {
                        HStack(alignment: .top, spacing: 12) {
                            editMetadataFieldRow(row[0], fixedWidth: firstColumnWidth, fillWidth: false)
                            editMetadataFieldRow(row[1], fillWidth: true)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            editMetadataFieldRow(row[0], fillWidth: true)
                            editMetadataFieldRow(row[1], fillWidth: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func editMetadataFieldRow(_ field: DetailField, fixedWidth: CGFloat? = nil, fillWidth: Bool) -> some View {
        let row = VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(field.label, text: metadataValueBinding(for: field.label), axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
        if let fixedWidth {
            row
                .frame(width: fixedWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else if fillWidth {
            row
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            row
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var substrateTagsBinding: Binding<String> {
        Binding(
            get: { lib.librarySampleEditDraft?.substrateTagsText ?? "" },
            set: { appState.library.updateLibrarySampleEditSubstrateTags($0) }
        )
    }

    func numericValueBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                lib.librarySampleEditDraft?
                    .numericValues
                    .first(where: { $0.key == key })?
                    .value ?? ""
            },
            set: { appState.library.updateLibrarySampleEditNumericValue(key: key, value: $0) }
        )
    }

    func metadataValueBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                lib.librarySampleEditDraft?
                    .metadataValues
                    .first(where: { $0.key == key })?
                    .value ?? ""
            },
            set: { appState.library.updateLibrarySampleEditMetadataValue(key: key, value: $0) }
        )
    }
    @ViewBuilder
    func detailSection(
        fields: [DetailField],
        availableWidth: CGFloat,
        sharedFirstColumnWidth: CGFloat?
    ) -> some View {
        let rows = computationService.groupedFields(fields)
        let sectionFirstColumnWidth = sharedFirstColumnWidth ?? computationService.sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                if row.count == 1 {
                    detailFieldRow(row[0], fillWidth: true)
                } else if let firstWidth = sectionFirstColumnWidth {
                    HStack(alignment: .top, spacing: 12) {
                        detailFieldRow(row[0], fixedWidth: firstWidth, fillWidth: false)
                        detailFieldRow(row[1], fillWidth: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        detailFieldRow(row[0], fillWidth: true)
                        detailFieldRow(row[1], fillWidth: true)
                    }
                }
            }
        }
    }

    func alignedFirstColumnWidth(fields: [DetailField], availableWidth: CGFloat) -> CGFloat? {
        computationService.alignedFirstColumnWidth(fields: fields, availableWidth: availableWidth)
    }

    @ViewBuilder
    func detailFieldRow(_ field: DetailField, fixedWidth: CGFloat? = nil, fillWidth: Bool) -> some View {
        let row = MetadataValueRow(label: field.label, value: field.value, monospaced: field.monospaced)
        if let fixedWidth {
            row
                .frame(width: fixedWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else if fillWidth {
            row
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            row
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func adaptiveDetailSectionSpacing(for height: CGFloat) -> CGFloat {
        computationService.adaptiveDetailSectionSpacing(for: height)
    }

    var sampleDetailSectionTitleFont: Font {
        AppFontScale.sectionHeader
    }

    @ViewBuilder
    func pendingChangesSection(for sample: LibrarySample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(selectedChangeHighlights(for: sample)) { change in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.key)
                            .font(.caption.weight(.semibold))
                        Text(change.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow.opacity(0.45), lineWidth: 0.8)
                )
            }
        }
    }

    func selectedChangeHighlights(for sample: LibrarySample) -> [ChangeHighlight] {
        computationService.selectedChangeHighlights(
            for: sample,
            sampleSyncChangesByID: lib.librarySampleSyncChangesByID,
            batchSyncChangesByID: lib.libraryBatchSyncChangesByID
        )
    }

    func syncStatusSymbol(for status: LibrarySyncBatchStatus) -> String {
        switch status {
        case .added:
            return "plus.circle.fill"
        case .changed:
            return "circle.fill"
        case .removed:
            return "minus.circle.fill"
        case .unchanged:
            return "circle"
        }
    }

    func syncStatusColor(for status: LibrarySyncBatchStatus) -> Color {
        switch status {
        case .added:
            return .green
        case .changed:
            return .yellow
        case .removed:
            return .red
        case .unchanged:
            return .secondary
        }
    }
}
