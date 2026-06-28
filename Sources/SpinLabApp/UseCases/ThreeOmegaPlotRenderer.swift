import Foundation

// MARK: - ThreeOmegaPlotRenderer
//
// Converts ThreeOmegaIngestionResult / ThreeOmegaScalingResult into
// WorkbenchPlotPayload and renders them to PNG Data + WorkbenchPlotLayout
// using WorkbenchChartRenderer / WorkbenchPlotLayout.

struct ThreeOmegaPlotRenderer {

    // MARK: - Scaling-law axis labels

    static let scalingXAxisLabel = #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#
    static let scalingYAxisLabel = #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#

    var workflowID: String = ""
    var showGrid: Bool = true
    var legendAnchor: String = ""           // "" = top-right (default)
    var legendPoint: CGPoint? = nil         // normalized free-position; overrides anchor
    var stackOffsetMultiplier: Double = 1.2 // spacing between stacked curves; 0 = no stacking
    var minGapFraction: Double = 0.15      // minimum gap as fraction of max peak-to-peak; 0 = no floor
    var titleTemplate: String = "#tab #method #device #sample"
    var titleTokens: [String: String] = [:]  // sample, numericDisplay keys

    // Display-only overrides applied after payload construction (mirrors AHEWorkspaceStore pattern)
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    var seriesLabelOverrides: [Int: String] = [:]
    var seriesRenderMode: SeriesRenderMode = .line
    var chartStyleOverrides: [String: String] = [:]
    var globalPlotDefaults: [String: String] = [:]
    var hiddenPointLabelsBySeries: [Int: Set<Int>] = [:]
    var axisRangeOverride: AxisRangeOverride? = nil
    var showPointTags: Bool = true

    private let defaultOptions = WorkbenchChartRenderer.Options()

    private enum RenderOutcome {
        case success(Data, WorkbenchPlotLayout, [String])
        case failure(String)
    }

    // MARK: - Render all analysis tabs (excludes scaling — geometry required)

    mutating func renderAllTabs(
        result: ThreeOmegaIngestionResult,
        seriesOrder1omega: [String]? = nil,
        seriesOrder3omega: [String]? = nil,
        rahe1Method: ThreeOmegaV3Method = .highField,
        rahe3Method: ThreeOmegaV3Method = .highField,
        rahe1DevMethod: ThreeOmegaV3Method = .highField,
        rahe3DevMethod: ThreeOmegaV3Method = .highField
    ) -> ThreeOmegaRenderedPlots {
        var allWarnings: [String] = []
        var plots = ThreeOmegaRenderedPlots()
        let r1 = renderR1omega(sweeps: result.fieldSweeps, device: result.device, seriesOrder: seriesOrder1omega)
        plots.r1omega = r1.0; plots.layoutR1omega = r1.1; plots.displayR1omega = r1.2; allWarnings.append(contentsOf: r1.3)
        let r3 = renderR3omega(sweeps: result.fieldSweeps, device: result.device, seriesOrder: seriesOrder3omega)
        plots.r3omega = r3.0; plots.layoutR3omega = r3.1; plots.displayR3omega = r3.2; allWarnings.append(contentsOf: r3.3)
        let rahe1 = renderRAHE1omegaVsT(sweeps: result.fieldSweeps, device: result.device, method: rahe1Method)
        plots.rahe1omegaVsT = rahe1.0; plots.layoutRAHE1omegaVsT = rahe1.1; plots.displayRAHE1omegaVsT = rahe1.2; allWarnings.append(contentsOf: rahe1.3)
        let rahe3 = renderRAHE3omegaVsT(sweeps: result.fieldSweeps, device: result.device, method: rahe3Method)
        plots.rahe3omegaVsT = rahe3.0; plots.layoutRAHE3omegaVsT = rahe3.1; plots.displayRAHE3omegaVsT = rahe3.2; allWarnings.append(contentsOf: rahe3.3)
        let rahe1d = renderRAHE1omegaVsDevice(sweeps: result.fieldSweeps, device: result.device, method: rahe1DevMethod)
        plots.rahe1omegaVsDevice = rahe1d.0; plots.layoutRAHE1omegaVsDevice = rahe1d.1; plots.displayRAHE1omegaVsDevice = rahe1d.2; allWarnings.append(contentsOf: rahe1d.3)
        let rahe3d = renderRAHE3omegaVsDevice(sweeps: result.fieldSweeps, device: result.device, method: rahe3DevMethod)
        plots.rahe3omegaVsDevice = rahe3d.0; plots.layoutRAHE3omegaVsDevice = rahe3d.1; plots.displayRAHE3omegaVsDevice = rahe3d.2; allWarnings.append(contentsOf: rahe3d.3)
        let hc = renderHcVsT(sweeps: result.fieldSweeps, device: result.device)
        plots.hcVsT = hc.0; plots.layoutHcVsT = hc.1; plots.displayHcVsT = hc.2; allWarnings.append(contentsOf: hc.3)
        if let rt = result.rtResult {
            let rtRendered = renderRT(rt: rt)
            plots.rtCurve = rtRendered.0; plots.layoutRTCurve = rtRendered.1; plots.displayRTCurve = rtRendered.2; allWarnings.append(contentsOf: rtRendered.3)
        }
        plots.pipelineWarnings = Array(Set(allWarnings))
        return plots
    }

    // MARK: - Individual tab renderers

    /// Tab 1: R(1ω) vs H, stacked by temperature
    func makeR1omegaPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        guard !sweeps.isEmpty else { return nil }
        let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(seriesOrder, to: sweeps)

        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: orderedSweeps.map { $0.r1omega },
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        let series = zip(orderedSweeps, offsets).map { (sweep, offset) in
            WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: sweep.r1omega.map { $0 + offset },
                sourceRef: sweep.stableSourceRef,
                sampleID: sweep.sampleID,
                metadata: sweep.sampleMetadata ?? [:]
            )
        }
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("R(1ω)", device: device, deviceMode: _deviceMode(for: device)),
            // Formula: R(1ω)(H) = V¹ω_X(H) / I_rms, centered, then stacked by temperature
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
            series: series,
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
    }

    mutating func renderR1omega(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeR1omegaPayload(sweeps: sweeps, device: device, seriesOrder: seriesOrder) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload, options: _stackedOptions(sweepCount: sweeps.count)), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 2: R(3ω) vs H, stacked by temperature
    func makeR3omegaPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        guard !sweeps.isEmpty else { return nil }
        let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(seriesOrder, to: sweeps)

        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: orderedSweeps.map { $0.r3omega },
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        let series = zip(orderedSweeps, offsets).map { (sweep, offset) in
            WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: sweep.r3omega.map { $0 + offset },
                sourceRef: sweep.stableSourceRef,
                sampleID: sweep.sampleID,
                metadata: sweep.sampleMetadata ?? [:]
            )
        }
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("R(3ω)", device: device, deviceMode: _deviceMode(for: device)),
            // Formula: R(3ω)(H) = V³ω_X(H) / I_rms, centered, then stacked by temperature
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(3ω) (Ω)"),
            series: series,
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
    }

    mutating func renderR3omega(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeR3omegaPayload(sweeps: sweeps, device: device, seriesOrder: seriesOrder) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload, options: _stackedOptions(sweepCount: sweeps.count)), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 3a: RAHE(1ω) vs T
    func makeRAHE1omegaVsTPayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        let temps = sweeps.compactMap { $0.rahe(harmonic: 1, method: method) != nil ? $0.temperatureK : nil }
        let vals  = sweeps.compactMap { $0.rahe(harmonic: 1, method: method) }
        guard !temps.isEmpty else { return nil }

        let methodTag = method == .highField ? "HFE" : "WA"
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("RAHE(1ω) (\(methodTag))", device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(1ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "RAHE(1ω)", x: temps, y: vals)]
        )
    }

    mutating func renderRAHE1omegaVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeRAHE1omegaVsTPayload(sweeps: sweeps, device: device, method: method) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 3b: RAHE(3ω) vs T
    func makeRAHE3omegaVsTPayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        let temps = sweeps.compactMap { $0.rahe(harmonic: 3, method: method) != nil ? $0.temperatureK : nil }
        let vals  = sweeps.compactMap { $0.rahe(harmonic: 3, method: method) }
        guard !temps.isEmpty else { return nil }

        let methodTag = method == .highField ? "HFE" : "WA"
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("RAHE(3ω) (\(methodTag))", device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(3ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "RAHE(3ω)", x: temps, y: vals)]
        )
    }

    mutating func renderRAHE3omegaVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeRAHE3omegaVsTPayload(sweeps: sweeps, device: device, method: method) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 3c: RAHE(1ω) vs Device angle
    func makeRAHE1omegaVsDevicePayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        return _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: 1, device: device, method: method)
    }

    mutating func renderRAHE1omegaVsDevice(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEVsDevice(sweeps: sweeps, harmonic: 1, device: device, method: method)
    }

    /// Tab 3d: RAHE(3ω) vs Device angle
    func makeRAHE3omegaVsDevicePayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        return _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: 3, device: device, method: method)
    }

    mutating func renderRAHE3omegaVsDevice(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEVsDevice(sweeps: sweeps, harmonic: 3, device: device, method: method)
    }

    private mutating func _renderRAHEVsDevice(
        sweeps: [ThreeOmegaFieldSweepResult],
        harmonic: Int,
        device: String,
        method: ThreeOmegaV3Method
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: harmonic, device: device, method: method) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var mutablePayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &mutablePayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    private func _makeRAHEVsDevicePayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        harmonic: Int,
        device: String,
        method: ThreeOmegaV3Method
    ) -> WorkbenchPlotPayload? {
        struct ParsedPoint {
            let angle: Double
            let rahe: Double
            let temperatureK: Double
        }
        let parsed: [ParsedPoint] = sweeps.compactMap { sweep in
            guard let angle = ThreeOmegaDeviceAngleParser.parseDegrees(sweep.device),
                  let rahe = sweep.rahe(harmonic: harmonic, method: method) else { return nil }
            return ParsedPoint(angle: angle, rahe: rahe, temperatureK: sweep.temperatureK)
        }
        guard !parsed.isEmpty else { return nil }

        let distinctTemps = Set(parsed.map { $0.temperatureK })
        if distinctTemps.count > 1 { return nil }

        let sorted = parsed.sorted { $0.angle < $1.angle }
        let hLabel = harmonic == 1 ? "1ω" : "3ω"
        let methodTag = method == .highField ? "HFE" : "WA"
        let tabKey = harmonic == 1 ? "rahe1omegaVsDevice" : "rahe3omegaVsDevice"
        let angleLabels = sorted.map { "\(Int($0.angle.rounded()))°" }

        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("RAHE(\(hLabel)) (\(methodTag))", device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: "Device angle (deg)", yField: "RAHE(\(hLabel)) (Ω)"),
            series: [WorkbenchPlotSeries(
                label: "RAHE(\(hLabel))",
                x: sorted.map(\.angle),
                y: sorted.map(\.rahe),
                renderMode: .scatter,
                renderModeLocked: true,
                pointLabels: angleLabels
            )],
            semanticParams: ["device": device, "tabKey": tabKey, "v3method": methodTag]
        )
    }

    /// Tab 3a multi-group: RAHE(1ω) vs T with overlays from multiple analysis packs
    mutating func renderRAHE1omegaVsTMulti(
        groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])],
        method: ThreeOmegaV3Method
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEMulti(groups: groups, harmonic: 1, method: method)
    }

    /// Tab 3b multi-group: RAHE(3ω) vs T with overlays from multiple analysis packs
    mutating func renderRAHE3omegaVsTMulti(
        groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])],
        method: ThreeOmegaV3Method
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEMulti(groups: groups, harmonic: 3, method: method)
    }

    private mutating func _renderRAHEMulti(
        groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])],
        harmonic: Int,
        method: ThreeOmegaV3Method
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        let hLabel = harmonic == 1 ? "1ω" : "3ω"
        let methodTag = method == .highField ? "HFE" : "WA"

        var series: [WorkbenchPlotSeries] = []
        for group in groups {
            let temps = group.sweeps.compactMap { $0.rahe(harmonic: harmonic, method: method) != nil ? $0.temperatureK : nil }
            let vals  = group.sweeps.compactMap { $0.rahe(harmonic: harmonic, method: method) }
            guard !temps.isEmpty else { continue }
            let sourceRef = group.sourceFiles.joined(separator: ";")
            series.append(WorkbenchPlotSeries(
                label: group.label,
                x: temps,
                y: vals,
                sourceRef: sourceRef.isEmpty ? nil : sourceRef
            ))
        }
        guard !series.isEmpty else { return (nil, nil, nil, []) }

        let device = groups.first?.sweeps.first?.device ?? ""
        let payload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("RAHE(\(hLabel)) (\(methodTag))", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(\(hLabel)) (Ω)"),
            series: series,
            semanticParams: ["device": device, "tabKey": harmonic == 1 ? "rahe1omegaVsT" : "rahe3omegaVsT", "v3method": methodTag]
        )
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 4: Hc¹ω and Hc³ω vs T
    func makeHcPayload(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> WorkbenchPlotPayload? {
        let temps1 = sweeps.compactMap { $0.hc1omega != nil ? $0.temperatureK : nil }
        let hc1    = sweeps.compactMap { $0.hc1omega }
        let temps3 = sweeps.compactMap { $0.hc3omega != nil ? $0.temperatureK : nil }
        let hc3    = sweeps.compactMap { $0.hc3omega }
        guard !temps1.isEmpty || !temps3.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        if !temps1.isEmpty { series.append(WorkbenchPlotSeries(label: "Hc¹ω", x: temps1, y: hc1)) }
        if !temps3.isEmpty { series.append(WorkbenchPlotSeries(label: "Hc³ω", x: temps3, y: hc3)) }

        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("Hc", device: device, deviceMode: _deviceMode(for: device)),
            // Formula: Hc = (|Hc⁺| + |Hc⁻|) / 2  (midpoint crossing on each branch)
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Hc (Oe)"),
            series: series
        )
    }

    mutating func renderHcVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeHcPayload(sweeps: sweeps, device: device) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 5: Rxx vs T (from RT file)
    func makeRTPayload(rt: ThreeOmegaRTResult) -> WorkbenchPlotPayload? {
        guard !rt.temperatureK.isEmpty else { return nil }
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("RT", device: rt.device, deviceMode: _deviceMode(for: rt.device)),
            // Formula: Rxx(T) = Col[9] = V¹ω_X / I_rms (pre-calculated in RT file)
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Rxx (Ω)"),
            series: [WorkbenchPlotSeries(label: "Rxx", x: rt.temperatureK, y: rt.rxx)]
        )
    }

    mutating func renderRT(rt: ThreeOmegaRTResult) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeRTPayload(rt: rt) else { return (nil, nil, nil, []) }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 6: Fig 5b — E^(3ω)_AHE / (E_xx³ × σ_xx) vs σ²_xx
    /// Display units: X in 10⁷ S²/cm², Y in Ω·μm³·V⁻²
    /// Conversions: X_SI (S/m)² × 1e-11 → 10⁷ S²/cm²
    ///              Y_SI (Ω·m³/V²) × 1e20 → Ω·μm³·V⁻² × 10²
    mutating func renderScaling(result: ThreeOmegaScalingResult, device: String = "", method: String = "") -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeScalingPayload(result: result, device: device, method: method) else {
            return (nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, layout, data != nil ? displayPayload : nil, w)
    }

    func makeScalingPayload(
        result: ThreeOmegaScalingResult,
        device: String = "",
        method: String = ""
    ) -> WorkbenchPlotPayload? {
        guard !result.points.isEmpty else { return nil }

        let xs = result.points.map { $0.sigma2xx * 1e-11 }   // (S/m)² → 10⁷ S²/cm²
        let ys = result.points.map { $0.scalingY  * 1e20  }  // Ω·m³/V² → Ω·μm³·V⁻² × 10²
        let tempLabels = result.points.map { "\(Int($0.temperatureK.rounded())) K" }
        var series: [WorkbenchPlotSeries] = [
            WorkbenchPlotSeries(label: "Experiment Data", x: xs, y: ys,
                                renderMode: .scatter, pointLabels: tempLabels)
        ]

        let isSingleFull = result.isSingleFullRange()
        for segment in result.segments {
            // Fit in display units: alpha_d = alpha_SI × 1e31, beta_d = beta_SI × 1e20
            let alphaD = segment.alpha * 1e31
            let betaD  = segment.beta  * 1e20

            // Compute fit line range using perpendicular projection of each data point
            // onto the line y = alphaD * x + betaD.
            // Foot x-coordinate: x_foot = (xi + alphaD * (yi - betaD)) / (1 + alphaD²)
            let denom = 1.0 + alphaD * alphaD
            let segPointIndices = result.points.enumerated().compactMap { i, pt in
                segment.participatingXValues.contains(pt.sigma2xx) ? i : nil
            }
            let footXs: [Double] = segPointIndices.map { i in
                let xi = result.points[i].sigma2xx * 1e-11
                let yi = result.points[i].scalingY * 1e20
                return (xi + alphaD * (yi - betaD)) / denom
            }
            let x0 = footXs.min() ?? (segment.participatingXValues.min() ?? 0) * 1e-11
            let x1 = footXs.max() ?? (segment.participatingXValues.max() ?? 0) * 1e-11
            let fitY = [x0, x1].map { alphaD * $0 + betaD }
            // Single full-range segment keeps the legacy label; partial/multi use temperature range
            let label = isSingleFull
                ? "Fitting Results"
                : "Fit \(Int(segment.tLo.rounded()))K–\(Int(segment.tHi.rounded()))K"
            series.append(WorkbenchPlotSeries(
                label: label,
                x: [x0, x1],
                y: fitY,
                renderModeLocked: true,
                lineWidth: 2.5
            ))
        }

        // Show R² in title only for single full-range fit
        let r2Str: String
        if isSingleFull, let seg = result.segments.first {
            r2Str = String(format: " R²=%.3f", seg.rSquared)
        } else {
            r2Str = ""
        }
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("Scaling Law", device: device, method: method, deviceMode: _deviceMode(for: device)) + r2Str,
            // Formula: Y = E^(3ω)_AHE / (E_xx³ × σ_xx) = α·σ²_xx + β
            // β → Q_xxz Berry curvature quadrupole; E_xx³ = E_xx to the power 3
            axisMapping: WorkbenchAxisMapping(
                xField: Self.scalingXAxisLabel,
                yField: Self.scalingYAxisLabel
            ),
            series: series
        )
    }

    // MARK: - Private

    /// Applies current style params (grid, legend), renders PNG and computes layout.
    /// Pass `options` to override the default size (e.g. for stacked waterfall plots).
    private mutating func _render(
        payload: inout WorkbenchPlotPayload,
        options: WorkbenchChartRenderer.Options? = nil
    ) -> RenderOutcome {
        var patch: [String: String] = [:]
        if showGrid { patch["showGrid"] = "true" }
        if !legendAnchor.isEmpty { patch["legendAnchor"] = legendAnchor }

        let input = WorkbenchRenderPipeline.Input(
            payload: payload,
            baseOptions: options ?? defaultOptions,
            legendPoint: legendPoint,
            globalPlotDefaults: globalPlotDefaults,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            seriesLabelOverrides: seriesLabelOverrides,
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            yLabelOverride: yLabelOverride,
            hiddenPointLabelsBySeries: hiddenPointLabelsBySeries,
            styleParamsPatch: patch,
            axisRangeOverride: axisRangeOverride,
            showPointTags: showPointTags
        )
        do {
            let output = try WorkbenchRenderPipeline.render(input)
            payload = output.manifestPayload
            return .success(output.imageData, output.layout, output.warnings)
        } catch {
            let reason = "pipeline failure: \(error)"
            fputs("[SpinLab] ThreeOmegaPlotRenderer: \(reason)\n", stderr)
            return .failure(reason)
        }
    }

    private func _consume(_ outcome: RenderOutcome, into warnings: inout [String]) -> (Data?, WorkbenchPlotLayout?) {
        switch outcome {
        case .success(let imageData, let layout, let w):
            warnings.append(contentsOf: w)
            return (imageData, layout)
        case .failure(let reason):
            warnings.append(reason)
            return (nil, nil)
        }
    }

    /// Computes chart height for stacked waterfall plots.
    /// Base 600px fits ~6 curves comfortably; each additional curve adds 40px.
    private func _stackedOptions(sweepCount: Int) -> WorkbenchChartRenderer.Options {
        var opts = defaultOptions
        opts.height = max(defaultOptions.height, defaultOptions.height + (sweepCount - 6) * 40)
        return opts
    }

    private func _defaultTitle(_ tabName: String, device: String, method: String = "", deviceMode: String = "single") -> String {
        var tokens = titleTokens
        tokens["tab"] = tabName
        if deviceMode == "single" {
            tokens["device"] = device
        } else {
            tokens["device"] = ""
            tokens["deviceMode"] = "angleSweep"
        }
        if !method.isEmpty { tokens["method"] = method }
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }

    private func _deviceMode(for device: String) -> String {
        device == "angle_sweep" ? "angleSweep" : "single"
    }

    func resolvedTitle(for tabName: String, device: String, method: String = "", deviceMode: String = "single") -> String {
        _defaultTitle(tabName, device: device, method: method, deviceMode: deviceMode)
    }

    private func _tempLabel(_ t: Double) -> String {
        "\(Int(t.rounded())) K"
    }
}
