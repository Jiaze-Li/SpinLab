import SwiftUI

/// Search route, middle column. Filters/executed flag live on the stable
/// `LibraryWorkspaceState`; matches are rebuilt here from current Library data.
@MainActor
struct LibrarySearchPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Bindable var state: LibraryWorkspaceState
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Search")
                .font(AppFontScale.sectionTitle)
            SearchWorkspaceSectionView(
                isExpanded: .constant(true),
                batchIdText: $state.searchBatchIdText,
                substrateText: $state.searchSubstrateText,
                keywordText: $state.searchKeywordText,
                thicknessText: $state.searchThicknessText,
                oxygenText: $state.searchOxygenText,
                temperatureText: $state.searchTemperatureText,
                energyText: $state.searchEnergyText,
                thicknessToleranceText: $state.searchThicknessToleranceText,
                oxygenToleranceText: $state.searchOxygenToleranceText,
                temperatureToleranceText: $state.searchTemperatureToleranceText,
                energyToleranceText: $state.searchEnergyToleranceText,
                searchHasExecuted: state.searchHasExecuted,
                searchMatchedResults: state.searchMatchedResults,
                onSearch: {
                    debounceTask?.cancel()
                    state.executeSearch(appState: appState)
                },
                onClear: {
                    debounceTask?.cancel()
                    state.clearSearchFilters()
                },
                onSelectResult: { state.selectSearchPreview($0) },
                isSelectedResult: { state.isSearchPreviewTarget($0) },
                resultListHeight: nil,
                showsHeader: false
            )
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Matches are not persisted: rebuild from the restored filters.
            if state.searchHasExecuted {
                state.executeSearch(appState: appState)
            }
        }
        .onChange(of: state.searchFingerprint) { _, _ in
            guard state.searchHasExecuted else { return }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                state.executeSearch(appState: appState)
            }
        }
        .onChange(of: appState.library.libraryExistingGroups) { _, _ in
            if state.searchHasExecuted {
                state.executeSearch(appState: appState)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }
}

/// Search route, right column: read-only sample summary + Open Sample. Never
/// reads or writes Drawer/Browser selection and exposes no edit/delete action.
@MainActor
struct LibrarySearchPreviewDetailView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Bindable var state: LibraryWorkspaceState
    private let computation = LibraryViewComputationService()

    var body: some View {
        if let sample = state.resolvedSearchPreviewSample(appState),
           let target = state.searchPreviewTarget {
            preview(sample: sample, target: target)
        } else {
            ContentUnavailableView(
                "No Sample Selected",
                systemImage: "magnifyingglass",
                description: Text("Select a search result to preview it here.")
            )
        }
    }

    private func preview(sample: LibrarySample, target: SearchPreviewTarget) -> some View {
        let sections = computation.makeDetailSections(for: sample)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Search Preview")
                        .font(AppFontScale.sectionTitle)
                    Spacer()
                    Button("Open Sample") {
                        appState.navigate(to: .libraryDrawer(
                            prefix: target.prefix, batchId: target.batchId, sampleId: target.sampleId
                        ))
                    }
                    .buttonStyle(.borderedProminent)
                }
                MetadataValueRow(label: "Sample", value: sample.displayName)
                MetadataValueRow(label: "Sample Key", value: sample.id, monospaced: true)
                MetadataValueRow(label: "Batch", value: "\(target.prefix)/\(sample.batchId)")
                MetadataValueRow(label: "Substrate", value: sample.substrateDisplay)
                MetadataValueRow(
                    label: "Substrate Tags",
                    value: sample.substrateTags.isEmpty ? "None" : sample.substrateTags.joined(separator: ", ")
                )
                if !sections.numericFields.isEmpty {
                    Divider()
                    Text("Numeric Tags").font(AppFontScale.sectionHeader)
                    fieldList(sections.numericFields)
                }
                Divider()
                Text("Metadata").font(AppFontScale.sectionHeader)
                if sections.metadataFields.isEmpty {
                    Text("No metadata").font(.caption).foregroundStyle(.secondary)
                } else {
                    fieldList(sections.metadataFields)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
        }
    }

    private func fieldList(_ fields: [DetailField]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields.indices, id: \.self) { index in
                MetadataValueRow(label: fields[index].label, value: fields[index].value, monospaced: fields[index].monospaced)
            }
        }
    }
}
