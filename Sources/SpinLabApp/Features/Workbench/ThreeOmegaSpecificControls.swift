import SwiftUI

// MARK: - 3ω controls adapter and Specific content
//
// Maps the 3ω store onto the shared Controls Surface (spec 06 §4.1, §5):
// - Plot Mode follows the *rendered* output of the active tab: Temperature Dependence is
//   `dualAxis`; every other tab is `cartesianXY`.
// - Specific groups: Transport Geometry · Fit Range (Scaling) · RAHE Method (RAHE device tabs) ·
//   Auxiliary Input (RT selection).
// The leaf inputs below take plain values and closures; this adapter is the only place that
// reads the store (CS-28).

extension ThreeOmegaWorkspaceStore: WorkbenchStandardPlotWorkspaceStore {}

extension ThreeOmegaWorkspaceStore {
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        let specific = controlsSpecificContent(appState: appState)
        guard tabs.activeTab == .temperatureDependence else {
            return standardControlsDescriptor(
                appState: appState,
                globalPlotDefaults: globalPlotDefaults,
                flushSource: "threeOmegaStyleChange",
                canReorderSeries: canReorderSeries,
                currentSeriesOrder: activeSeriesOrder,
                // #method exists only on the Scaling tab; #device is empty for angle sweeps.
                rendererTitleTokens: tabs.activeTab == .scaling ? ["tab", "device", "method"] : ["tab", "device"],
                specific: specific
            )
        }
        return temperatureDependenceControlsDescriptor(
            appState: appState, globalPlotDefaults: globalPlotDefaults, specific: specific)
    }

    @MainActor
    private func temperatureDependenceControlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>,
        specific: WorkbenchSpecificContent
    ) -> WorkbenchControlsDescriptor {
        let output = tabs.output(for: .temperatureDependence)
        let payload = output.dualAxisPayload
        let sourceToken = tabs.activeSourceIdentityKey
        let rerender: () -> Void = { self.rerenderTemperatureDependenceForDualAxisControlChange() }
        // Persisted change (title template, typography, tick counts): re-render and flush.
        let onDisplayStateChange: () -> Void = {
            rerender()
            appState.scheduleInteractionSnapshotFlush(source: "threeOmegaDualAxisControlChange")
        }
        let displayState = temperatureDependenceDisplayState

        let common = WorkbenchCommonControlsModel(
            showTitle: displayState.showTitle,
            titleOverride: displayState.titleOverride,
            renderedTitle: payload?.title ?? "",
            sourceResetToken: sourceToken,
            globalPlotDefaults: globalPlotDefaults,
            titleTemplate: Binding(get: { self.titleTemplate }, set: { self.titleTemplate = $0 }),
            // The Temperature Dependence renderer supplies only #tab beside the data tokens.
            availableTokens: WorkbenchTitleTokens.available(renderer: ["tab"], data: titleDataTokens),
            onShowTitleChange: { value in
                self.temperatureDependenceDisplayState.showTitle = value
                onDisplayStateChange()
            },
            onTitleOverride: { value in
                guard self.temperatureDependenceDisplayState.titleOverride != value else { return }
                self.temperatureDependenceDisplayState.titleOverride = value
                rerender()
            },
            onTitleTemplateChange: onDisplayStateChange,
            onStyleChange: onDisplayStateChange
        )

        let plot = DualAxisControlsModel(
            displayState: Binding(
                get: { self.temperatureDependenceDisplayState },
                set: { self.temperatureDependenceDisplayState = $0 }),
            globalPlotDefaults: globalPlotDefaults,
            chartStyleOverrides: Binding(
                get: { self.tabs.chartStyleOverrides },
                set: { self.tabs.chartStyleOverrides = $0 }),
            activeLayout: output.dualAxisLayout,
            sourceResetToken: sourceToken,
            renderedXLabel: payload?.xLabel ?? "",
            renderedLeftYLabel: payload?.leftYLabel ?? "",
            renderedRightYLabel: payload?.rightYLabel ?? "",
            onDisplayStateChange: onDisplayStateChange,
            // Axis ranges, labels and per-series style are per-tab display state, not snapshot
            // fields: re-render only, no flush.
            onTransientChange: rerender,
            onResetRanges: {
                self.temperatureDependenceDisplayState.axisRangeOverride = nil
                rerender()
            }
        )
        return WorkbenchControlsDescriptor(common: common, plot: .dualAxis(plot), specific: specific)
    }

    @MainActor
    func controlsSpecificContent(appState: SpinLabAppState) -> WorkbenchSpecificContent {
        let tab = tabs.activeTab
        let commitGeometry: () -> Void = {
            print("[PERF][scaling] geometry commit")
            self.refreshTransportDerivedPlots(reason: "geometry changed")
            appState.scheduleInteractionSnapshotFlush(source: "threeOmegaGeometryChange")
        }
        let commitFitRanges: () -> Void = {
            print("[PERF][scaling] fitRange commit")
            self.refreshTransportDerivedPlots(reason: "fit ranges changed")
            appState.scheduleInteractionSnapshotFlush(source: "threeOmegaFitRangesChange")
        }
        let showsGeometry = tab == .scaling || tab == .temperatureDependence
        let rtSelection = rtSelectionInput(appState: appState)
        let ranges = fitRanges

        return WorkbenchSpecificContent {
            if showsGeometry {
                WorkbenchSpecificGroup("transportGeometry", title: "Transport Geometry") {
                    WorkbenchSpecificRow("geometry") {
                        WorkbenchSpecificInput.control("lxx", ThreeOmegaGeometryNumberInput(
                            label: "Lxx", unit: "μm", placeholder: "26", labelWidth: 36, fieldWidth: 44...60,
                            value: Binding(get: { self.geometry.lxx }, set: { self.geometry.lxx = $0 }),
                            onCommit: commitGeometry))
                        WorkbenchSpecificInput.control("lxy", ThreeOmegaGeometryNumberInput(
                            label: "Lxy", unit: "μm", placeholder: "21", labelWidth: 36, fieldWidth: 44...60,
                            value: Binding(get: { self.geometry.lxy }, set: { self.geometry.lxy = $0 }),
                            onCommit: commitGeometry))
                        WorkbenchSpecificInput.control("d", ThreeOmegaGeometryNumberInput(
                            label: "d", unit: "nm", placeholder: "30", labelWidth: 24, fieldWidth: 40...52,
                            value: Binding(get: { self.geometry.dNm }, set: { self.geometry.dNm = $0 }),
                            onCommit: commitGeometry))
                        WorkbenchSpecificInput.control("v3Method", ThreeOmegaV3MethodInput(
                            method: Binding(get: { self.v3Method }, set: { self.v3Method = $0 }),
                            onCommit: commitGeometry))
                    }
                }
            }
            if tab == .scaling {
                WorkbenchSpecificGroup("fitRange", title: "Fit Range") {
                    WorkbenchSpecificRow("ranges", label: "Fit range") {
                        for (index, range) in ranges.enumerated() {
                            WorkbenchSpecificInput.control("range\(index)", ThreeOmegaFitRangeInput(
                                label: ranges.count == 1 ? "T" : "T\(index + 1)",
                                canRemove: ranges.count > 1,
                                showsAdd: ranges.count == 1,
                                tLo: Binding(
                                    get: { index < self.fitRanges.count ? self.fitRanges[index].tLo : nil },
                                    set: { if index < self.fitRanges.count { self.fitRanges[index].tLo = $0 } }),
                                tHi: Binding(
                                    get: { index < self.fitRanges.count ? self.fitRanges[index].tHi : nil },
                                    set: { if index < self.fitRanges.count { self.fitRanges[index].tHi = $0 } }),
                                onCommit: commitFitRanges,
                                onAdd: { self.addFitRange(); commitFitRanges() },
                                onRemove: { self.removeFitRange(id: range.id); commitFitRanges() }))
                        }
                        if ranges.count > 1 {
                            WorkbenchSpecificInput.control("addRange", ThreeOmegaAddFitRangeInput(
                                onAdd: { self.addFitRange(); commitFitRanges() }))
                        }
                    }
                }
            }
            if tab == .rahe1omegaVsDevice || tab == .rahe3omegaVsDevice {
                WorkbenchSpecificGroup("raheMethod", title: "RAHE Method") {
                    WorkbenchSpecificRow("method", label: "RAHE Method") {
                        WorkbenchSpecificInput.menu(
                            "picker",
                            selection: Binding<ThreeOmegaV3Method>(
                                get: { self.activeRAHEMethod ?? .highField },
                                set: { self.updateRAHEMethod($0) }),
                            options: ThreeOmegaV3Method.allCases.map { (title: $0.rawValue, value: $0) })
                    }
                }
            }
            WorkbenchSpecificGroup("auxiliaryInput", title: "Auxiliary Input") {
                WorkbenchSpecificRow("rtSelection", label: "RT file") {
                    WorkbenchSpecificInput.control("search", fills: true, rtSelection)
                }
            }
        }
    }

    @MainActor
    private func rtSelectionInput(appState: SpinLabAppState) -> ThreeOmegaRTSelectionInput {
        let libraryRoot = appState.library.librarySettings.rootPath
        let search: () -> Void = {
            self.clearRTSelection()
            appState.workbench.runThreeOmegaRTSearch(
                libraryRootPath: libraryRoot,
                librarySettings: appState.library.librarySettings)
        }
        let hits = rtSearchResults.map { hit in
            ThreeOmegaRTHitRow(
                id: hit.id,
                fileName: hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id,
                conditionSummary: hit.conditionSummary)
        }
        return ThreeOmegaRTSelectionInput(
            query: Binding(get: { self.rtQuery }, set: { self.updateRTQuery($0) }),
            showPopover: Binding(get: { self.showRTPopover }, set: { self.showRTPopover = $0 }),
            isSearching: isRTSearching,
            canSearch: !rtQuery.trimmingCharacters(in: .whitespaces).isEmpty && !isRTSearching && libraryRoot != nil,
            selectedFileName: selectedRTHit.map { $0.measurementFilePath.components(separatedBy: "/").last ?? $0.id },
            searchMessage: rtSearchMessage,
            hits: hits,
            onSearch: search,
            onSelect: { id in
                guard let hit = self.rtSearchResults.first(where: { $0.id == id }) else { return }
                self.selectRTHit(hit)
                appState.scheduleInteractionSnapshotFlush(source: "threeOmegaRTHitSelect")
            })
    }
}

// MARK: - Leaf inputs

private extension ThreeOmegaV3Method {
    var geometryDisplayLabel: String {
        switch self {
        case .highField: return "HFE"
        case .window: return "WA"
        }
    }
}

/// Label + numeric field + unit as one input. Edits accumulate in local text state and commit
/// on Return or focus loss, so clicking away never silently discards a typed value.
struct ThreeOmegaGeometryNumberInput: WorkbenchLeafInput {
    let label: String
    let unit: String
    let placeholder: String
    let labelWidth: CGFloat
    let fieldWidth: ClosedRange<CGFloat>
    @Binding var value: Double
    let onCommit: () -> Void

    @State private var text: String = ""
    @State private var didAppear = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
                .frame(width: labelWidth, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: fieldWidth.lowerBound, idealWidth: fieldWidth.upperBound, maxWidth: fieldWidth.upperBound)
                .focused($focused)
                .onAppear {
                    guard !didAppear else { return }
                    didAppear = true
                    text = Self.format(value)
                }
                .onChange(of: value) { _, newValue in
                    let formatted = Self.format(newValue)
                    if text != formatted { text = formatted }
                }
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            Text(unit)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let parsed = WorkbenchNumericFieldText.parseFinite(trimmed) else {
            text = Self.format(value)
            return
        }
        guard parsed != value else { return }
        value = parsed
        onCommit()
    }

    private static func format(_ value: Double) -> String {
        WorkbenchNumericFieldText.formatIntegerIfExact(value)
    }
}

struct ThreeOmegaV3MethodInput: WorkbenchLeafInput {
    @Binding var method: ThreeOmegaV3Method
    let onCommit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text("V(3ω)")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Picker("", selection: $method) {
                ForEach(ThreeOmegaV3Method.allCases) { method in
                    Text(method.geometryDisplayLabel).tag(method)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 84, idealWidth: 104, maxWidth: 104, alignment: .leading)
            .help(method.rawValue)
            .accessibilityLabel("V(3ω) method \(method.rawValue)")
            .onChange(of: method) { _, _ in onCommit() }
        }
    }
}

/// One fit range: `Fit n  [T_lo] to [T_hi]  (−) (+)`. Blank clears a bound.
struct ThreeOmegaFitRangeInput: WorkbenchLeafInput {
    let label: String
    let canRemove: Bool
    let showsAdd: Bool
    @Binding var tLo: Double?
    @Binding var tHi: Double?
    let onCommit: () -> Void
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            ThreeOmegaFitRangeBoundField(placeholder: "T_lo (K)", value: $tLo, onCommit: onCommit)
            Text("to")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(.secondary)
                .fixedSize()
            ThreeOmegaFitRangeBoundField(placeholder: "T_hi (K)", value: $tHi, onCommit: onCommit)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .accessibilityLabel("Remove fit range")
            .disabled(!canRemove)
            if showsAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .accessibilityLabel("Add fit range")
            }
        }
    }
}

struct ThreeOmegaAddFitRangeInput: WorkbenchLeafInput {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            Label("Add fit range", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }
}

private struct ThreeOmegaFitRangeBoundField: View {
    let placeholder: String
    @Binding var value: Double?
    let onCommit: () -> Void

    @State private var text: String = ""
    @State private var didAppear = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 68)
            .focused($focused)
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                text = Self.format(value)
            }
            .onChange(of: value) { _, newValue in
                let formatted = Self.format(newValue)
                if text != formatted { text = formatted }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard value != nil else { return }
            value = nil
            onCommit()
        } else if let parsed = WorkbenchNumericFieldText.parseFinite(trimmed) {
            guard parsed != value else { return }
            value = parsed
            onCommit()
        } else {
            text = Self.format(value)
        }
    }

    private static func format(_ value: Double?) -> String {
        value.map(WorkbenchNumericFieldText.formatRoundedIfRepresentable) ?? ""
    }
}

struct ThreeOmegaRTHitRow: Identifiable, Equatable {
    let id: String
    let fileName: String
    let conditionSummary: String
}

/// RT file search: query field, search button, result popover and the selected file name.
struct ThreeOmegaRTSelectionInput: WorkbenchLeafInput {
    @Binding var query: String
    @Binding var showPopover: Bool
    let isSearching: Bool
    let canSearch: Bool
    let selectedFileName: String?
    let searchMessage: String?
    let hits: [ThreeOmegaRTHitRow]
    let onSearch: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppSpacing.xs) {
                TextField("RT file…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: 140, maxWidth: .infinity)
                    .onSubmit { onSearch() }
                    .popover(isPresented: $showPopover, arrowEdge: .bottom) { popover }
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Search RT files")
                .disabled(!canSearch)
            }
            if let selectedFileName {
                Text("✓ \(selectedFileName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(selectedFileName)
            }
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching…").font(.system(size: 12))
                }
            } else if hits.isEmpty {
                Text(searchMessage ?? "No results.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(searchMessage ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hits) { hit in
                            Button { onSelect(hit.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.fileName).font(.system(size: 12)).lineLimit(1)
                                    Text(hit.conditionSummary)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.08)))
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 360)
            }
        }
        .padding(8)
        .frame(width: 320)
    }
}
