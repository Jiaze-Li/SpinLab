import AppKit
import SwiftUI
import Testing
@testable import SpinLabApp

/// The real Controls Surface for every real workflow: the actual stores, the actual adapters,
/// a real SwiftUI layout pass at the representative widths (AC5, AC8). Members come from
/// `WorkbenchWorkflowKind.allCases`, so a new workflow is covered without editing a list.
@MainActor
@Suite("Controls Surface — all workflows (real stores, real layout)", .rulesGlobalState)
struct ControlsSurfaceWorkflowTests {
    private typealias F = ControlsSurfaceFixtures

    private func descriptor(_ kind: WorkbenchWorkflowKind, _ appState: SpinLabAppState) -> WorkbenchControlsDescriptor {
        kind.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
    }

    private func host(_ descriptor: WorkbenchControlsDescriptor, width: CGFloat) -> ControlsSurfaceHost<WorkbenchControlsSurface> {
        ControlsSurfaceHost(width: width) { WorkbenchControlsSurface(descriptor: descriptor) }
    }

    /// (id, frame) pairs of one section in reading order.
    private func signature(_ host: ControlsSurfaceHost<WorkbenchControlsSurface>, section: String) -> [(id: String, frame: CGRect)] {
        SurfaceSnapshots.sectionFrames(host.probe, section)
    }
    private typealias Frames = [(id: String, frame: CGRect)]

    /// Same controls in the same order, at the same positions and sizes (1 pt tolerance for
    /// sub-pixel rounding between separately hosted views). Frames are relative to the section top.
    /// `ignoring` skips the frames of ids whose geometry legitimately follows the data (the
    /// Available token hint, CS-8/CS-9): their presence and order are still compared.
    private func sameLayout(_ a: Frames, _ b: Frames, ignoring: (String) -> Bool = { _ in false }) -> String? {
        guard a.map(\.id) == b.map(\.id) else {
            return "ids differ: \(Set(a.map(\.id)).symmetricDifference(Set(b.map(\.id))).sorted())"
        }
        for (x, y) in zip(a, b) where !ignoring(x.id) {
            let d = [abs(x.frame.minX - y.frame.minX), abs(x.frame.minY - y.frame.minY),
                     abs(x.frame.width - y.frame.width), abs(x.frame.height - y.frame.height)].max() ?? 0
            if d > 1.0 { return "\(x.id) frame \(x.frame) vs \(y.frame)" }
        }
        return nil
    }

    @Test("Every workflow's Surface has sound geometry at 300/364/420/520/720 pt")
    func geometryForEveryWorkflow() async {
        await SurfaceSnapshots.prepare()
        for kind in WorkbenchWorkflowKind.allCases {
            for width in F.representativeWidths {
                let facts = SurfaceSnapshots.facts(kind, width)
                #expect(facts.problems.isEmpty, "\(kind)@\(Int(width)): \(facts.problems)")
                #expect(facts.ids.contains { $0.hasPrefix("controls.common.") }, "\(kind) mounts Common")
                #expect(facts.ids.contains { $0.hasPrefix("controls.plot.") }, "\(kind) mounts Plot")
                if facts.hasSpecific {
                    #expect(facts.ids.contains { $0.hasPrefix("controls.specific.") }, "\(kind) mounts Specific")
                }
            }
        }
    }

    /// Common's composition is identical for every workflow: same ids in the same order, and the
    /// non-template controls on the same lines with the same heights. The template group's own
    /// geometry and the horizontal split it causes follow the data (its Available hint, CS-9).
    private func sameCommon(_ a: Frames, _ b: Frames) -> String? {
        guard a.map(\.id) == b.map(\.id) else {
            return "ids differ: \(Set(a.map(\.id)).symmetricDifference(Set(b.map(\.id))).sorted())"
        }
        for (x, y) in zip(a, b) where !x.id.hasPrefix("controls.common.titleTemplate") {
            if abs(x.frame.minY - y.frame.minY) > 1 || abs(x.frame.height - y.frame.height) > 1 {
                return "\(x.id) line/height \(x.frame) vs \(y.frame)"
            }
        }
        return nil
    }

    @Test("Common is the same component for all seven workflows (ids, order, position, width)")
    func commonIdentityAcrossWorkflows() async {
        await SurfaceSnapshots.prepare()
        for width in F.representativeWidths {
            let reference = SurfaceSnapshots.facts(.ahe, width).common
            #expect(reference.count >= 4)
            for kind in WorkbenchWorkflowKind.allCases {
                let problem = sameCommon(SurfaceSnapshots.facts(kind, width).common, reference)
                #expect(problem == nil, "\(kind) Common differs @\(Int(width)): \(problem ?? "")")
            }
        }
    }

    @Test("IV and AFM Common are identical; AFM and RSM Common and Heatmap Plot are identical")
    func ivAfmAndAfmRsmIdentity() async {
        await SurfaceSnapshots.prepare()
        for width in F.representativeWidths {
            let iv = SurfaceSnapshots.facts(.iv, width), afm = SurfaceSnapshots.facts(.afm, width), rsm = SurfaceSnapshots.facts(.rsm, width)
            #expect(sameCommon(iv.common, afm.common) == nil, "IV vs AFM Common @\(Int(width))")
            #expect(sameCommon(afm.common, rsm.common) == nil, "AFM vs RSM Common @\(Int(width))")
            // The Heatmap-specific modules are identical; Typography and Axes follow the declared
            // capability configuration (axis-free AFM, RSM with X/Y), checked separately.
            let heatmapOnly: (Frames) -> Frames = { $0.filter { !$0.id.contains(".axisLabels") && !$0.id.contains(".ticks") && !$0.id.contains(".typography") } }
            // The Z-range group fills the rest of its line, so its width follows the Axes modules.
            let plot = sameLayout(heatmapOnly(afm.plot), heatmapOnly(rsm.plot), ignoring: { $0.hasPrefix("controls.plot.zRange") })
            #expect(plot == nil, "AFM vs RSM Heatmap Plot-Specific modules @\(Int(width)): \(plot ?? "")")
            #expect(!afm.plot.isEmpty)
        }
    }

    @Test("Cartesian XY workflows share one Plot layout")
    func cartesianPlotIdentity() async {
        await SurfaceSnapshots.prepare()
        let kinds: [WorkbenchWorkflowKind] = [.ahe, .iv, .rt, .xyRotation, .threeOmega]
        for width in F.representativeWidths {
            let reference = SurfaceSnapshots.facts(.ahe, width).plot
            for kind in kinds {
                let problem = sameLayout(SurfaceSnapshots.facts(kind, width).plot, reference)
                #expect(problem == nil, "\(kind) Plot differs @\(Int(width)): \(problem ?? "")")
            }
        }
    }

    @Test("Visual contract on real stores: IV 364/520/720, AFM 364, RSM 364, 3ω DualAxis 420")
    func visualContractEvidence() {
        let appState = SpinLabAppState()
        appState.workbench.threeOmegaWorkspace.tabs.activeTab = .temperatureDependence
        let cases: [(WorkbenchWorkflowKind, [CGFloat])] = [(.ahe, [520, 720]), (.iv, [364, 520, 720]), (.afm, [364]), (.rsm, [364]), (.threeOmega, [420])]
        let commonRoles: [String: WorkbenchTextRole] = [
            "controls.common.showTitle.checkbox": .label, "controls.common.plotTitle.field": .label,
            "controls.common.titleTemplate.field": .label, "controls.common.transparent.checkbox": .label,
        ]
        for (kind, widths) in cases {
            for width in widths {
                let h = host(descriptor(kind, appState), width: width)
                #expect(ControlsGeometry.problems(h.probe, width: width).isEmpty, "\(kind)@\(Int(width))")
                #expect(ControlsGeometry.roleProblems(h.probe, expecting: commonRoles).isEmpty, "\(kind)@\(Int(width))")
                let common = signature(h, section: "common").filter { $0.id.split(separator: ".").count == 3 }
                    .map { "\($0.id.split(separator: ".").last!)@\(Int($0.frame.minX)),\(Int($0.frame.minY))+\(Int($0.frame.width))" }
                // Optional screenshots for the visual review: SPINLAB_LAYOUT_SNAPSHOT_DIR=<dir> swift test …
                if let dir = ProcessInfo.processInfo.environment["SPINLAB_LAYOUT_SNAPSHOT_DIR"], let png = h.snapshotPNG() {
                    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(kind)-\(Int(width)).png"))
                }
                let fr = h.probe.frames
                func box(_ id: String) -> String { fr[id].map { "\(Int($0.minX.rounded())),\(Int($0.minY.rounded()))+\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "-" }
                let plotLines = Set(ControlsGeometry.groupIDs(h.probe).filter { $0.hasPrefix("controls.plot.") }.compactMap { fr[$0]?.minY.rounded() }).count
                let gaps = ControlsGeometry.groupIDs(h.probe).filter { $0.hasPrefix("controls.plot.") }.compactMap { fr[$0] }
                    .sorted { ($0.minY.rounded(), $0.minX) < ($1.minY.rounded(), $1.minX) }
                let trailing = Dictionary(grouping: gaps, by: { $0.minY.rounded() }).values.map { Int(width - ($0.map(\.maxX).max() ?? 0)) }.sorted()
                print("[LAYOUT-FRAMES] \(kind) \(Int(width))pt templateInput=\(box("controls.common.titleTemplate.field#content")) available=\(box("controls.common.titleTemplate.available")) plotLines=\(plotLines) trailingBlankPerLine=\(trailing) font=\(box("controls.plot.typography")) axisX=\(box("controls.plot.axisLabels.x#content")) axisY=\(box("controls.plot.axisLabels.y#content")) gap=\(box("controls.plot.spacing"))")
                print("[LAYOUT-EVIDENCE] \(kind) \(Int(width))pt undersized=\(h.probe.undersizedControls.count) baselineIssues=\(ControlsGeometry.baselineProblems(h.probe).count) common=\(common)")
            }
        }
    }

    @Test("3ω picks the Plot Mode from the rendered output of the active tab")
    func threeOmegaTabsSelectPlotMode() {
        let appState = SpinLabAppState()
        let store = appState.workbench.threeOmegaWorkspace
        for tab in ThreeOmegaWorkbenchTab.allCases {
            store.tabs.activeTab = tab
            let mode = descriptor(.threeOmega, appState).plot.mode
            #expect(mode == (tab == .temperatureDependence ? .dualAxis : .cartesianXY), "\(tab)")
            #expect(WorkbenchWorkflowKind.threeOmega.controlsPlotModes.contains(mode))
        }
    }

    @Test("Every control has exactly one owner: Specific groups per workflow match the spec")
    func specificGroupsMatchSpec() {
        let appState = SpinLabAppState()
        func groups(_ kind: WorkbenchWorkflowKind) -> [String] { descriptor(kind, appState).specific.groups.map(\.id) }
        #expect(groups(.ahe) == ["metricOverrides"])
        #expect(groups(.iv) == ["input", "channels", "fitting", "angular"])
        #expect(groups(.rt).isEmpty, "RT has no Specific section")
        #expect(groups(.xyRotation) == ["dataCorrection", "plotAnnotation", "calibration"])
        #expect(groups(.rsm) == ["viewSelection", "zLabel"])
        #expect(groups(.afm) == ["dataChannel", "processing", "plotDecoration"])

        let threeOmega = appState.workbench.threeOmegaWorkspace
        threeOmega.tabs.activeTab = .scaling
        #expect(groups(.threeOmega) == ["transportGeometry", "fitRange", "auxiliaryInput"])
        threeOmega.tabs.activeTab = .temperatureDependence
        #expect(groups(.threeOmega) == ["transportGeometry", "auxiliaryInput"])
        threeOmega.tabs.activeTab = .rahe1omegaVsDevice
        #expect(groups(.threeOmega) == ["raheMethod", "auxiliaryInput"])
        threeOmega.tabs.activeTab = .fieldSweep1omega
        #expect(groups(.threeOmega) == ["auxiliaryInput"])
    }

    @Test("Heatmap capability configurations: RSM has Shared Axes + Axis/Ticks fonts, axis-free AFM has only the Title font")
    func heatmapCapabilityConfigurations() async {
        let appState = SpinLabAppState()
        func model(_ kind: WorkbenchWorkflowKind) -> HeatmapControlsModel? {
            if case .heatmap(let m) = descriptor(kind, appState).plot { return m }
            return nil
        }
        guard let rsm = model(.rsm), let afm = model(.afm) else { Issue.record("AFM and RSM are heatmap workflows"); return }
        #expect(rsm.fontRoles == [.title, .axis, .ticks])
        #expect(rsm.axes.labels.map(\.role) == [.x, .y])
        #expect(rsm.axes.ticks.map(\.role) == [.x, .y])
        #expect(rsm.axes.ranges.isEmpty, "RSM spatial ranges are not implemented and not offered")
        #expect(afm.fontRoles == [.title])
        #expect(afm.axes.isEmpty, "AFM draws no spatial axes")

        await SurfaceSnapshots.prepare()
        let rsmIDs = Set(SurfaceSnapshots.facts(.rsm, 520).ids), afmIDs = Set(SurfaceSnapshots.facts(.afm, 520).ids)
        for id in ["controls.plot.axisLabels.x", "controls.plot.axisLabels.y", "controls.plot.ticks.row",
                   "controls.plot.typography.row", "controls.specific.zLabel.zLabel"] {
            #expect(rsmIDs.contains(id), "RSM has \(id)")
        }
        #expect(afmIDs.contains("controls.plot.typography.row"))
        #expect(!afmIDs.contains { $0.contains(".axisLabels") || $0.contains(".ticks") }, "AFM has no Axes module")
        // Nothing of RSM's former Axis Controls group remains in Specific.
        #expect(!rsmIDs.contains { $0.contains("controls.specific.axisControls") })
        #expect(!rsmIDs.contains { $0.hasPrefix("controls.specific.") && ($0.contains("xLabel") || $0.contains("yLabel") || $0.contains("fontSizes")) })
    }

    @Test("Axes follow the declared roles: X/Y for Cartesian and Heatmap with axes, X/L-Y/R-Y for DualAxis")
    func axisRolesPerPlotMode() async {
        await SurfaceSnapshots.prepare()
        func labelRoles(_ ids: [String]) -> Set<String> {
            Set(ids.compactMap { $0.hasPrefix("controls.plot.axisLabels.") && !$0.contains("#") && $0.split(separator: ".").count == 4 && !$0.hasSuffix(".row") ? String($0.split(separator: ".")[3]) : nil })
        }
        #expect(labelRoles(SurfaceSnapshots.facts(.ahe, 520).ids) == ["x", "y"])
        #expect(labelRoles(SurfaceSnapshots.facts(.rsm, 520).ids) == ["x", "y"])
        #expect(labelRoles(SurfaceSnapshots.facts(.afm, 520).ids).isEmpty)
    }

    /// With group titles hidden (CS-18a) every Specific row must still say what it is. A row
    /// without a row label is accepted only when its inputs carry their own visible label
    /// (typed toggles, or a leaf that draws "X basis", "Lxx", "Hc", …). The list below is that
    /// review: a new unlabeled row fails here until someone reviews it.
    @Test("Specific rows keep a clear label after group titles are hidden")
    func specificRowsStayLabelled() {
        let selfLabelled: Set<String> = [
            "ahe/metricOverrides.unsupported", "ahe/metricOverrides.hc", "ahe/metricOverrides.rahe", "ahe/metricOverrides.pendingHint",
            "iv/input.currentBasis", "iv/fitting.fit", "iv/angular.angular",
            "xyRotation/dataCorrection.corrections", "xyRotation/plotAnnotation.annotation",
            "threeOmega/transportGeometry.geometry",
            "rsm/viewSelection.view",
        ]
        let appState = SpinLabAppState()
        var unlabeled: Set<String> = []
        for kind in WorkbenchWorkflowKind.allCases {
            for tab in kind == .threeOmega ? ThreeOmegaWorkbenchTab.allCases.map(Optional.some) : [nil] {
                if let tab { appState.workbench.threeOmegaWorkspace.tabs.activeTab = tab }
                for group in descriptor(kind, appState).specific.groups {
                    for row in group.rows where row.rowLabel == nil { unlabeled.insert("\(kind)/\(group.id).\(row.id)") }
                }
            }
        }
        #expect(unlabeled.subtracting(selfLabelled).isEmpty, "unreviewed unlabeled Specific rows: \(unlabeled.subtracting(selfLabelled).sorted())")
        // The channel pickers, the φ offsets, the fit ranges and the RT file would be ambiguous without their group title.
        for (kind, group, row) in [(WorkbenchWorkflowKind.iv, "channels", "channels"), (.xyRotation, "calibration", "phiOffset")] {
            let found = descriptor(kind, appState).specific.groups.first { $0.id == group }?.rows.first { $0.id == row }
            #expect(found?.rowLabel != nil, "\(kind) \(group).\(row) needs its own label")
        }
    }

    @Test("No Specific group title is drawn in any workflow at any width")
    func specificTitlesHiddenEverywhere() async {
        await SurfaceSnapshots.prepare()
        for kind in WorkbenchWorkflowKind.allCases {
            for width in F.representativeWidths {
                #expect(!SurfaceSnapshots.facts(kind, width).ids.contains { $0.hasSuffix("#title") }, "\(kind)@\(Int(width))")
            }
        }
    }

    @Test("AFM Scale Bar variants (off/auto/manual) keep sound geometry at narrow widths")
    func afmScaleBarVariants() {
        let appState = SpinLabAppState()
        let store = appState.workbench.afmWorkspace
        for setting in [
            AFMScaleBarSetting(mode: .off),
            AFMScaleBarSetting(mode: .auto),
            AFMScaleBarSetting(mode: .manual, manualLengthMicrometers: 2, color: .black),
        ] {
            store.scaleBar = setting
            let h = host(descriptor(.afm, appState), width: 300)
            for width in [300, 380, 520] as [CGFloat] {
                h.resize(to: width)
                let problems = ControlsGeometry.problems(h.probe, width: width)
                #expect(problems.isEmpty, "scale bar \(setting.mode)@\(Int(width)): \(problems)")
            }
            let ids = Set(h.probe.frames.keys)
            #expect(ids.contains("controls.specific.plotDecoration.barText") == (setting.mode != .off))
            #expect(ids.contains("controls.specific.plotDecoration.barLength") == (setting.mode == .manual))
        }
    }

    @Test("Layout changes keep the same stable identifiers for every workflow")
    func identifiersStableAcrossWidths() async {
        await SurfaceSnapshots.prepare()
        for kind in WorkbenchWorkflowKind.allCases {
            let narrow = SurfaceSnapshots.facts(kind, 300).ids
            for width in F.representativeWidths {
                #expect(SurfaceSnapshots.facts(kind, width).ids == narrow, "\(kind)@\(Int(width)): ids must not depend on width")
            }
        }
    }

    // MARK: State and callbacks reach the real stores

    @Test("Common and Cartesian Plot edits write to the workflow store (AHE)")
    func commonAndPlotEditsReachStore() throws {
        let appState = SpinLabAppState()
        let store = appState.workbench.aheWorkspace
        let d = descriptor(.ahe, appState)

        d.common.onShowTitleChange(false)
        #expect(store.tabs.activeState.showTitle == false)
        d.common.onShowTitleChange(true)
        #expect(store.tabs.activeState.showTitle == true)

        guard case .cartesianXY(let plot) = d.plot else { Issue.record("AHE must be cartesianXY"); return }
        plot.minGapFraction.wrappedValue = 0.3
        #expect(store.minGapFraction == 0.3)
        plot.showGrid.wrappedValue.toggle()
        #expect(store.showPlotGrid == plot.showGrid.wrappedValue)
        d.common.titleTemplate.wrappedValue = "#tab #sample"
        #expect(store.titleTemplate == "#tab #sample")
    }

    @Test("AHE Hc and R_AHE override edits reach the pending override state")
    func aheOverridesReachStore() {
        let appState = SpinLabAppState()
        let store = appState.workbench.aheWorkspace
        store.updateHcCandidate(rawValue: "1.5", rawReason: "manual")
        #expect(store.pendingMetricOverride?.proposedValue == 1.5)
        store.updateRAHECandidate(rawValue: "2.5", rawReason: "manual")
        #expect(store.pendingRAHEOverride?.proposedValue == 2.5)
        // The Specific content now offers Clear for both pending overrides.
        let group = store.controlsSpecificContent.groups.first { $0.id == "metricOverrides" }
        #expect(group?.rows.map(\.id) == ["hc", "rahe", "pendingHint"])
    }

    @Test("Heatmap Plot and RSM Specific callbacks update the display state (RSM)")
    func heatmapCallbacksReachStore() {
        let appState = SpinLabAppState()
        let store = appState.workbench.rsmWorkspace
        let d = descriptor(.rsm, appState)
        guard case .heatmap(let plot) = d.plot else { Issue.record("RSM must be heatmap"); return }
        plot.onShowColorbarChange(false)
        #expect(store.heatmapDisplayState.showColorbar == false)
        plot.onInterpolationModeChange(.logSpaceGaussian1p5x)
        #expect(store.heatmapDisplayState.interpolationMode == .logSpaceGaussian1p5x)
        d.common.onTitleOverride("My title")
        #expect(store.heatmapDisplayState.titleOverride == "My title")
        d.common.onShowTitleChange(false)
        #expect(store.heatmapDisplayState.showTitle == false)
    }

    @Test("3ω Temperature Dependence Common edits write the DualAxis display state")
    func threeOmegaTemperatureDependenceCommon() {
        let appState = SpinLabAppState()
        let store = appState.workbench.threeOmegaWorkspace
        store.tabs.activeTab = .temperatureDependence
        let d = descriptor(.threeOmega, appState)
        d.common.onShowTitleChange(false)
        #expect(store.temperatureDependenceDisplayState.showTitle == false)
        d.common.onTitleOverride("TD title")
        #expect(store.temperatureDependenceDisplayState.titleOverride == "TD title")
    }
}

/// One real-layout pass per workflow, shared by every identity/geometry test above: the
/// stores and hosts are built once (host creation dominates the cost) and resized across the
/// representative widths. Uses its own app state, so other tests cannot disturb it.
@MainActor
private enum SurfaceSnapshots {
    struct Facts {
        var problems: [String]
        var ids: [String]
        var common: [(id: String, frame: CGRect)]
        var plot: [(id: String, frame: CGRect)]
        var hasSpecific: Bool
    }

    private static var table: [WorkbenchWorkflowKind: [CGFloat: Facts]] = [:]
    private static var building: Task<Void, Never>?

    /// Builds the table once. Yields between workflows and widths so no single main-actor
    /// block is long enough to starve unrelated time-based tests in the same run.
    static func prepare() async {
        if building == nil { building = Task { @MainActor in await build() } }
        await building?.value
    }

    static func facts(_ kind: WorkbenchWorkflowKind, _ width: CGFloat) -> Facts { table[kind]![width]! }

    private static func section(_ probe: WorkbenchLayoutProbe, _ name: String) -> [(id: String, frame: CGRect)] {
        sectionFrames(probe, name)
    }

    /// Frames of one section in reading order, relative to the section's top edge so a taller
    /// section above (data-dependent hint text) does not shift the comparison.
    static func sectionFrames(_ probe: WorkbenchLayoutProbe, _ name: String) -> [(id: String, frame: CGRect)] {
        let entries = probe.frames.filter { $0.key.hasPrefix("controls.\(name).") }
        let top = entries.values.map(\.minY).min() ?? 0
        return entries
            .sorted { ($0.value.minY.rounded(), $0.value.minX.rounded(), $0.key) < ($1.value.minY.rounded(), $1.value.minX.rounded(), $1.key) }
            .map { (id: $0.key, frame: $0.value.offsetBy(dx: 0, dy: -top)) }
    }

    private static func build() async {
        let appState = SpinLabAppState()
        // Z-range inner rows depend on the Z-domain mode (data state): compare at equal state.
        appState.workbench.rsmWorkspace.updateHeatmapZDomainState(appState.workbench.afmWorkspace.heatmapDisplayState.zDomainState)
        for kind in WorkbenchWorkflowKind.allCases {
            let d = kind.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:]))
            let host = ControlsSurfaceHost(width: ControlsSurfaceFixtures.representativeWidths[0]) { WorkbenchControlsSurface(descriptor: d) }
            await Task.yield()
            var perWidth: [CGFloat: Facts] = [:]
            for width in ControlsSurfaceFixtures.representativeWidths {
                host.resize(to: width)
                await Task.yield()
                perWidth[width] = Facts(
                    problems: ControlsGeometry.problems(host.probe, width: width),
                    ids: host.probe.frames.keys.sorted(),
                    common: section(host.probe, "common"), plot: section(host.probe, "plot"),
                    hasSpecific: !d.specific.isEmpty)
            }
            table[kind] = perWidth
        }
    }
}
