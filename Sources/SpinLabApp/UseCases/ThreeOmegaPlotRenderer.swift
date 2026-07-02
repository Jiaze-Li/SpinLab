import Foundation

// MARK: - ThreeOmegaPlotRenderer
//
// Converts ThreeOmegaIngestionResult / ThreeOmegaScalingResult into
// WorkbenchPlotPayload and renders them to PNG Data + WorkbenchPlotLayout
// using WorkbenchChartRenderer / WorkbenchPlotLayout.

struct ThreeOmegaPlotRenderer {

    // MARK: - Axis / legend label constants

    // Keep these in the same lightweight math-text style as the Scaling Law tab.
    // The PlotSystem parser expects the `math:` prefix and understands subscript/superscript
    // fragments such as σ_{xx}^{2}, R_{AHE}^{1ω}, and E_{AHE}^{3ω}.
    static let fieldAxisLabel = "H (T)"
    static let temperatureAxisLabel = "T (K)"
    static let deviceAngleAxisLabel = "Device angle (deg)"

    static let r1AxisLabel = #"math:R^{1ω} (Ω)"#
    static let r3AxisLabel = #"math:R^{3ω} (Ω)"#
    static let rAHE1AxisLabel = #"math:R_{AHE}^{1ω} (Ω)"#
    static let rAHE3AxisLabel = #"math:R_{AHE}^{3ω} (Ω)"#
    static let hcAxisLabel = #"math:H_{c} (Oe)"#
    static let rxxAxisLabel = #"math:R_{xx} (Ω)"#
    static let sigmaXXAxisLabel = #"math:σ_{xx} (S/m)"#
    static let eAHEOverE3AxisLabel = #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#

    static let scalingXAxisLabel = #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#
    static let scalingYAxisLabel = #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#

    static let rAHE1LegendLabel = #"math:R_{AHE}^{1ω}"#
    static let rAHE3LegendLabel = #"math:R_{AHE}^{3ω}"#
    static let hc1LegendLabel = #"math:H_{c}^{1ω}"#
    static let hc3LegendLabel = #"math:H_{c}^{3ω}"#
    static let rxxLegendLabel = #"math:R_{xx}"#
    static let eAHEOverE3LegendLabel = #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#
    static let sigmaXXLegendLabel = #"math:σ_{xx}"#

    var workflowID: String = WorkflowKey.threeOmega.rawValue
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

    private struct StackedFieldSweepPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
        let warnings: [String]
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
        makeR1omegaPayloads(sweeps: sweeps, device: device, seriesOrder: seriesOrder, hiddenSeriesKeys: [])?.manifestPayload
    }

    mutating func renderR1omega(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads = makeR1omegaPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        ) else {
            return (nil, nil, nil, [])
        }
        var renderPayload = payloads.displayPayload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload, options: _stackedOptions(sweepCount: sweeps.count)), into: &w)
        w.append(contentsOf: payloads.warnings)
        return (data, layout, data != nil ? payloads.displayPayload : nil, w)
    }

    /// Tab 2: R(3ω) vs H, stacked by temperature
    func makeR3omegaPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        makeR3omegaPayloads(sweeps: sweeps, device: device, seriesOrder: seriesOrder, hiddenSeriesKeys: [])?.manifestPayload
    }

    mutating func renderR3omega(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads = makeR3omegaPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        ) else {
            return (nil, nil, nil, [])
        }
        var renderPayload = payloads.displayPayload
        var w: [String] = []
        let (data, layout) = _consume(_render(payload: &renderPayload, options: _stackedOptions(sweepCount: sweeps.count)), into: &w)
        w.append(contentsOf: payloads.warnings)
        return (data, layout, data != nil ? payloads.displayPayload : nil, w)
    }

    private func makeR1omegaPayloads(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> StackedFieldSweepPayloads? {
        makeStackedFieldSweepPayloads(
            sweeps: sweeps,
            device: device,
            yValueForSweep: { $0.r1omega },
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaR1omegaVsH,
            yAxisLabel: Self.r1AxisLabel,
            plotTitle: "R(1ω)"
        )
    }

    private func makeR3omegaPayloads(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> StackedFieldSweepPayloads? {
        makeStackedFieldSweepPayloads(
            sweeps: sweeps,
            device: device,
            yValueForSweep: { $0.r3omega },
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaR3omegaVsH,
            yAxisLabel: Self.r3AxisLabel,
            plotTitle: "R(3ω)"
        )
    }

    private func makeStackedFieldSweepPayloads(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        yValueForSweep: (ThreeOmegaFieldSweepResult) -> [Double],
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String],
        tabKey: String,
        yAxisLabel: String,
        plotTitle: String
    ) -> StackedFieldSweepPayloads? {
        guard !sweeps.isEmpty else { return nil }
        let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(seriesOrder, to: sweeps)

        let rawSeries = orderedSweeps.map { sweep in
            let stableID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: sweep.stableSourceRef,
                sampleID: sweep.sampleID,
                fallback: sweep.device
            ) ?? sweep.device
            return WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: yValueForSweep(sweep),
                sourceRef: sweep.stableSourceRef,
                sampleID: sweep.sampleID,
                metadata: _seriesMetadata(
                    base: sweep.sampleMetadata ?? [:],
                    tabKey: tabKey,
                    seriesRole: "sweep",
                    stableSemanticID: stableID
                )
            )
        }

        let visibility = filterHiddenStackSeries(rawSeries, hiddenSeriesKeys: hiddenSeriesKeys)
        let visibleSeries = visibility.series
        let stackInputSeries = visibility.ignoredAllHidden ? rawSeries : visibleSeries
        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: stackInputSeries.map(\.y),
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        let displaySeries = zip(stackInputSeries, offsets).map { pair in
            let (series, offset) = pair
            guard offset != 0 else { return series }
            var shifted = series
            shifted.y = series.y.map { $0 + offset }
            return shifted
        }
        let warning = visibility.ignoredAllHidden ? ["series visibility ignored: all series were hidden"] : []

        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle(plotTitle, device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: Self.fieldAxisLabel, yField: yAxisLabel),
            series: rawSeries,
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle(plotTitle, device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: Self.fieldAxisLabel, yField: yAxisLabel),
            series: displaySeries,
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        return StackedFieldSweepPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: warning
        )
    }

    /// Tab 3a: R_AHE(1ω) vs T
    func makeRAHE1omegaVsTPayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        let temps = sweeps.compactMap { $0.rahe(harmonic: 1, method: method) != nil ? $0.temperatureK : nil }
        let vals  = sweeps.compactMap { $0.rahe(harmonic: 1, method: method) }
        guard !temps.isEmpty else { return nil }

        let methodTag = method == .highField ? "HFE" : "WA"
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("R_AHE(1ω) (\(methodTag))", device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: Self.rAHE1AxisLabel),
            series: [WorkbenchPlotSeries(
                label: Self.rAHE1LegendLabel,
                x: temps,
                y: vals,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE1omegaVsT,
                    seriesRole: "series",
                    stableSemanticID: "rahe-1omega"
                )
            )]
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

    /// Tab 3b: R_AHE(3ω) vs T
    func makeRAHE3omegaVsTPayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        let temps = sweeps.compactMap { $0.rahe(harmonic: 3, method: method) != nil ? $0.temperatureK : nil }
        let vals  = sweeps.compactMap { $0.rahe(harmonic: 3, method: method) }
        guard !temps.isEmpty else { return nil }

        let methodTag = method == .highField ? "HFE" : "WA"
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("R_AHE(3ω) (\(methodTag))", device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: Self.rAHE3AxisLabel),
            series: [WorkbenchPlotSeries(
                label: Self.rAHE3LegendLabel,
                x: temps,
                y: vals,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE3omegaVsT,
                    seriesRole: "series",
                    stableSemanticID: "rahe-3omega"
                )
            )]
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

    /// Tab 3c: R_AHE(1ω) vs Device angle
    func makeRAHE1omegaVsDevicePayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        return _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: 1, device: device, method: method)
    }

    mutating func renderRAHE1omegaVsDevice(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEVsDevice(sweeps: sweeps, harmonic: 1, device: device, method: method)
    }

    /// Tab 3d: R_AHE(3ω) vs Device angle
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
            // Diagnose why: if parsed points exist but span multiple temperatures, emit a diagnostic.
            let parsed = sweeps.compactMap { sweep -> Double? in
                guard ThreeOmegaDeviceAngleParser.parseDegrees(sweep.device) != nil,
                      sweep.rahe(harmonic: harmonic, method: method) != nil else { return nil }
                return sweep.temperatureK
            }
            if Set(parsed).count > 1 {
                let hLabel = harmonic == 1 ? "1ω" : "3ω"
                let warning = "R_AHE(\(hLabel)) vs Device: mixed temperatures detected — chart requires a single temperature. Select sweeps from one temperature only."
                return (nil, nil, nil, [warning])
            }
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
        let yLabel = harmonic == 1 ? Self.rAHE1AxisLabel : Self.rAHE3AxisLabel
        let legendLabel = harmonic == 1 ? Self.rAHE1LegendLabel : Self.rAHE3LegendLabel

        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("R_AHE(\(hLabel)) (\(methodTag))", device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: Self.deviceAngleAxisLabel, yField: yLabel),
            series: [WorkbenchPlotSeries(
                label: legendLabel,
                x: sorted.map(\.angle),
                y: sorted.map(\.rahe),
                renderMode: .scatter,
                renderModeLocked: true,
                pointLabels: angleLabels,
                metadata: _seriesMetadata(
                    tabKey: harmonic == 1 ? WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE1omegaVsDevice : WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE3omegaVsDevice,
                    seriesRole: "series",
                    stableSemanticID: harmonic == 1 ? "rahe-1omega" : "rahe-3omega"
                )
            )],
            semanticParams: ["device": device, "tabKey": tabKey, "v3method": methodTag]
        )
    }

    /// Tab 3a multi-group: R_AHE(1ω) vs T with overlays from multiple analysis packs
    mutating func renderRAHE1omegaVsTMulti(
        groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])],
        method: ThreeOmegaV3Method
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEMulti(groups: groups, harmonic: 1, method: method)
    }

    /// Tab 3b multi-group: R_AHE(3ω) vs T with overlays from multiple analysis packs
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
        let yLabel = harmonic == 1 ? Self.rAHE1AxisLabel : Self.rAHE3AxisLabel

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
                sourceRef: sourceRef.isEmpty ? nil : sourceRef,
                metadata: _seriesMetadata(
                    tabKey: harmonic == 1 ? WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE1omegaVsT : WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE3omegaVsT,
                    seriesRole: "overlay",
                    stableSemanticID: sourceRef.isEmpty ? group.sweeps.compactMap(\.sourceFilePath).joined(separator: ";") : sourceRef
                )
            ))
        }
        guard !series.isEmpty else { return (nil, nil, nil, []) }

        let device = groups.first?.sweeps.first?.device ?? ""
        let payload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("R_AHE(\(hLabel)) (\(methodTag))", device: device),
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: yLabel),
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
        if !temps1.isEmpty {
            series.append(WorkbenchPlotSeries(
                label: Self.hc1LegendLabel,
                x: temps1,
                y: hc1,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaHcVsT,
                    seriesRole: "series",
                    stableSemanticID: "hc-1omega"
                )
            ))
        }
        if !temps3.isEmpty {
            series.append(WorkbenchPlotSeries(
                label: Self.hc3LegendLabel,
                x: temps3,
                y: hc3,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaHcVsT,
                    seriesRole: "series",
                    stableSemanticID: "hc-3omega"
                )
            ))
        }

        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle("H_c", device: device, deviceMode: _deviceMode(for: device)),
            // Formula: Hc = (|Hc⁺| + |Hc⁻|) / 2  (midpoint crossing on each branch)
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: Self.hcAxisLabel),
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
            title: _defaultTitle("R_xx(T)", device: rt.device, deviceMode: _deviceMode(for: rt.device)),
            // Formula: Rxx(T) = Col[9] = V¹ω_X / I_rms (pre-calculated in RT file)
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: Self.rxxAxisLabel),
            series: [WorkbenchPlotSeries(
                label: Self.rxxLegendLabel,
                x: rt.temperatureK,
                y: rt.rxx,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRT,
                    seriesRole: "series",
                    stableSemanticID: "rxx"
                )
            )]
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

    /// Tab 7: Temperature Dependence — E_AHE^(3ω) / E_xx^3 and σxx vs T
    /// Left axis uses the derived left-hand quantity from the scaling result:
    /// E_AHE^(3ω) / E_xx^3 = scalingY × σxx.
    mutating func renderTemperatureDependence(result: ThreeOmegaScalingResult) -> (Data?, DualAxisPlotLayout?, DualAxisPlotPayload?, [String]) {
        guard var payload = makeTemperatureDependencePayload(result: result) else {
            return (nil, nil, nil, [])
        }
        if !titleOverride.isEmpty {
            payload.title = titleOverride
        }
        if !xLabelOverride.isEmpty {
            payload.xLabel = xLabelOverride
        }
        if !yLabelOverride.isEmpty {
            payload.leftYLabel = yLabelOverride
        }
        var w: [String] = []
        let input = DualAxisRenderPipeline.Input(
            payload: payload,
            style: WorkbenchChartStyle.from(styleParams: globalPlotDefaults.merging(chartStyleOverrides) { _, new in new })
        )
        do {
            let output = try DualAxisRenderPipeline.render(input)
            w.append(contentsOf: output.warnings)
            return (output.imageData, output.layout, payload, w)
        } catch {
            let reason = "dual-axis pipeline failure: \(error)"
            fputs("[SpinLab] ThreeOmegaPlotRenderer: \(reason)\n", stderr)
            return (nil, nil, nil, [reason])
        }
    }

    func makeTemperatureDependencePayload(result: ThreeOmegaScalingResult) -> DualAxisPlotPayload? {
        guard !result.points.isEmpty else { return nil }

        let seriesPoints: [(temperatureK: Double, sigmaXX: Double, leftY: Double)] = result.points.map { point in
            let sigmaXX = sqrt(max(0, point.sigma2xx))
            return (
                temperatureK: point.temperatureK,
                sigmaXX: sigmaXX,
                leftY: point.scalingY * sigmaXX
            )
        }

        let x = seriesPoints.map(\.temperatureK)
        let leftY = seriesPoints.map(\.leftY)
        let rightY = seriesPoints.map(\.sigmaXX)

        return DualAxisPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: "Temperature Dependence",
            xLabel: Self.temperatureAxisLabel,
            leftYLabel: Self.eAHEOverE3AxisLabel,
            rightYLabel: Self.sigmaXXAxisLabel,
            leftSeries: [
                DualAxisPlotSeries(
                    label: Self.eAHEOverE3LegendLabel,
                    x: x,
                    y: leftY
                )
            ],
            rightSeries: [
                DualAxisPlotSeries(
                    label: Self.sigmaXXLegendLabel,
                    x: x,
                    y: rightY
                )
            ]
        )
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
            WorkbenchPlotSeries(
                label: "Experiment Data",
                x: xs,
                y: ys,
                renderMode: .scatter,
                pointLabels: tempLabels,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaScaling,
                    seriesRole: "series",
                    stableSemanticID: "eAHE3w-over-exx3"
                )
            )
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
                lineWidth: 2.5,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaScaling,
                    seriesRole: "fit",
                    stableSemanticID: "fit:\(Int(segment.tLo.rounded()))-\(Int(segment.tHi.rounded()))"
                )
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

    private func _seriesMetadata(
        base: [String: String] = [:],
        tabKey: String,
        seriesRole: String,
        stableSemanticID: String
    ) -> [String: String] {
        WorkbenchSeriesIdentityMetadata.metadata(
            base: base,
            seriesIdentityKey: WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                workflowID: workflowID,
                tabKey: tabKey,
                seriesRole: seriesRole,
                stableSemanticID: stableSemanticID
            )
        )
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
