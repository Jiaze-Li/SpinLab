import SwiftUI

/// 3ω AHE workflow workspace.
///
/// Layout:
///   Left column  — search, analyze button, geometry inputs, results list
///   Right column — 6 tab strip + plot canvas + fit parameters (Fig 5b)
struct ThreeOmegaWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell {
            ThreeOmegaLeftColumn()
                .environment(appState)
        } rightColumn: {
            ThreeOmegaRightColumn()
                .environment(appState)
        }
    }
}

// MARK: - Left column

private struct ThreeOmegaLeftColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Fixed controls
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline) {
                    Text("3ω AHE")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.top, 4)

                ThreeOmegaSearchSection()
                    .environment(appState)

                ThreeOmegaGeometryPanel()
                    .environment(appState)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            ThreeOmegaResultsList()
                .environment(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Search + action buttons

private struct ThreeOmegaSearchSection: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var workbench = appState.workbench
        let store = appState.workbench.threeOmegaWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        VStack(alignment: .leading, spacing: 8) {
            TextField("3ω, PN69, 5K …", text: $workbench.workflowSearchQueryText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 4) {
                Text("Library Root:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(libraryRoot ?? "Not configured — set in Library settings")
                    .font(.caption)
                    .foregroundStyle(libraryRoot == nil ? .red : .secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button("Search") {
                    workbench.runWorkflowMeasurementSearch(libraryRootPath: libraryRoot)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workbench.isWorkflowSearchRunning || libraryRoot == nil)

                Button("Analyze") {
                    store.runAnalysis()
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedSearchResultIDs.isEmpty || store.isAnalyzing)

                Button("Clear") {
                    store.clearAll()
                    workbench.clearWorkflowMeasurementSearch()
                }
                .buttonStyle(.bordered)

                if workbench.isWorkflowSearchRunning || store.isAnalyzing {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Geometry panel

private struct ThreeOmegaGeometryPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        GroupBox("Geometry (for Fig 5b scaling)") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("L_xx (μm):")
                        .frame(width: 80, alignment: .trailing)
                    TextField("e.g. 26", value: $store.geometry.lxx, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                HStack {
                    Text("L_xy (μm):")
                        .frame(width: 80, alignment: .trailing)
                    TextField("e.g. 21", value: $store.geometry.lxy, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                HStack {
                    Text("d (nm):")
                        .frame(width: 80, alignment: .trailing)
                    TextField("e.g. 30", value: $store.geometry.dNm, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                Button("Run Scaling") {
                    appState.workbench.threeOmegaWorkspace.runScaling()
                }
                .buttonStyle(.bordered)
                .disabled(!store.geometry.isComplete || store.ingestionResult == nil)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Results list

private struct ThreeOmegaResultsList: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let workbench = appState.workbench
        let store = workbench.threeOmegaWorkspace

        if workbench.workflowSearchResults.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let msg = workbench.workflowSearchMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Run a search to find 3ω AHE measurements.")
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workbench.workflowSearchResults) { hit in
                        ThreeOmegaResultRow(
                            hit: hit,
                            isSelected: store.selectedSearchResultIDs.contains(hit.id)
                        )
                        .onTapGesture {
                            store.toggleSearchHitSelection(hit.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct ThreeOmegaResultRow: View {
    let hit: WorkflowMeasurementSearchHit
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(hit.sampleKey)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(URL(fileURLWithPath: hit.sourceFilePath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !hit.conditionSummary.isEmpty && hit.conditionSummary != "-" {
                    Text(hit.conditionSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Right column

private struct ThreeOmegaRightColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        VStack(alignment: .leading, spacing: 0) {

            // Tab strip
            HStack(spacing: 0) {
                ForEach(ThreeOmegaWorkbenchTab.allCases) { tab in
                    Button(tab.rawValue) {
                        store.activeTab = tab
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(store.activeTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if store.activeTab == tab {
                            Rectangle()
                                .frame(height: 2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {

                    // Status
                    WorkbenchStatusArea(
                        searchMessage: nil,
                        plotMessage: store.analysisMessage,
                        loadMessage: nil
                    )

                    // Plot canvas for active tab
                    WorkbenchPlotCanvas(
                        imageData: activeTabImageData(store),
                        layout: nil,
                        seriesLabelOverrides: [:],
                        onLegendDrag: { _ in },
                        onEditTitle: { _ in },
                        onEditXLabel: { _ in },
                        onEditYLabel: { _ in },
                        onEditLegendLabel: { _, _ in }
                    )

                    // Fig 5b fit parameters (shown only on scaling tab)
                    if store.activeTab == .scaling, let sr = store.scalingResult {
                        ThreeOmegaScalingResultPanel(result: sr)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
    }

    private func activeTabImageData(_ store: ThreeOmegaWorkspaceStore) -> Data? {
        switch store.activeTab {
        case .fieldSweep1omega: return store.plotR1omega
        case .fieldSweep3omega: return store.plotR3omega
        case .raheVsT:          return store.plotRAHEvsT
        case .hcVsT:            return store.plotHcvsT
        case .rtCurve:          return store.plotRT
        case .scaling:          return store.plotScaling
        }
    }
}

// MARK: - Scaling result panel (Fig 5b fit parameters)

private struct ThreeOmegaScalingResultPanel: View {
    let result: ThreeOmegaScalingResult

    var body: some View {
        GroupBox("Fig 5b Fit Results") {
            VStack(alignment: .leading, spacing: 4) {
                if let beta = result.beta {
                    Text(String(format: "β (Q_xxz) = %.4e", beta))
                        .font(.system(.body, design: .monospaced))
                }
                if let alpha = result.alpha {
                    Text(String(format: "α (skew) = %.4e", alpha))
                        .font(.system(.body, design: .monospaced))
                }
                if let r2 = result.rSquared {
                    Text(String(format: "R² = %.4f", r2))
                        .font(.system(.body, design: .monospaced))
                }
                Text("\(result.points.count) data point(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(result.warnings, id: \.self) { w in
                    Text("⚠ \(w)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
