import SwiftUI

/// 3ω workflow workspace — left column (search/action bar/plot controls/results).
struct ThreeOmegaWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace
        @Bindable var workbench = appState.workbench

        WorkflowWorkspaceLeftColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            controls: store.controlsDescriptor(
                appState: appState,
                globalPlotDefaults: $workbench.globalPlotDefaults
            ),
            searchExtra: { EmptyView() },
            leftExtra: { EmptyView() },
            actionBarTrailing: {
                ThreeOmegaActionBarTabPicker()
                    .environment(appState)
            }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=ThreeOmega")
        }
    }
}

/// 3ω workflow workspace — right column (results/status/scaling law summary).
struct ThreeOmegaWorkspaceRightView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        WorkflowWorkspaceRightColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            rightExtra: {
                if store.tabs.activeTab == .scaling {
                    VStack(alignment: .leading, spacing: 12) {
                        ThreeOmegaTransportStatusPanel(status: store.transportDerivedStatus)
                            .equatable()
                        if let sr = store.scalingResult {
                            ThreeOmegaScalingResultPanel(result: sr)
                                .equatable()
                        }
                    }
                }
            }
        )
    }
}

// MARK: - Action-bar tab picker (all 3ω tabs)

/// Tab picker only — rendered in the workflow action bar's trailing slot, after Load.
/// Stack offset / gap belong to the shared Cartesian XY Plot section.
private struct ThreeOmegaActionBarTabPicker: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        WorkbenchPlotTabPicker(
            activeTab: $store.tabs.activeTab,
            tabs: ThreeOmegaWorkbenchTab.visibleTabs,
            tabLabel: { $0.rawValue },
            onChange: { oldValue, newValue in
                print("[PERF][tabs] activeTab changed old=\(oldValue) new=\(newValue)")
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "threeOmegaTabSwitch")
            }
        )
    }
}

/// Takes the status value directly (rather than reading through the store)
/// so `Equatable` reflects exactly what this panel renders — a tab switch or
/// style/font edit elsewhere in the workspace does not change `status` and so
/// does not force a rebuild via `.equatable()`.
private struct ThreeOmegaTransportStatusPanel: View {
    let status: ThreeOmegaTransportDerivedStatus

    var body: some View {
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build statusPanel") } }()

        GroupBox("Scaling Status") {
            VStack(alignment: .leading, spacing: 6) {
                switch status {
                case .idle:
                    Text("Scaling Law waits for Analyze.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .refreshing:
                    Text("Updating Scaling Law…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .missing(let requirements):
                    Text("Scaling Law unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Missing: \(requirements.map(\.rawValue).joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.orange)
                case .ready:
                    Text("Scaling Law is up to date.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .unavailable(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

extension ThreeOmegaTransportStatusPanel: Equatable {}

// MARK: - Scaling result panel

private struct ThreeOmegaScalingResultPanel: View {
    let result: ThreeOmegaScalingResult

    var body: some View {
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build resultPanel") } }()
        GroupBox("Scaling Law Fit Results") {
            VStack(alignment: .leading, spacing: 6) {
                if result.isSingleFullRange(), let seg = result.segments.first {
                    Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "R² = %.4f", seg.rSquared))
                        .font(.system(.body, design: .monospaced))
                    Text("\(result.points.count) data point(s)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(result.segments.enumerated()), id: \.element.id) { idx, seg in
                        if idx > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(seg.tLo.rounded())) K – \(Int(seg.tHi.rounded())) K  (n=\(seg.pointCount))")
                                .font(.callout.bold())
                                .foregroundStyle(.secondary)
                            Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                                .font(.system(.callout, design: .monospaced))
                            Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                                .font(.system(.callout, design: .monospaced))
                            Text(String(format: "R² = %.4f", seg.rSquared))
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                ForEach(result.warnings, id: \.self) { w in
                    Text("⚠ \(w)")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

extension ThreeOmegaScalingResultPanel: Equatable {}
