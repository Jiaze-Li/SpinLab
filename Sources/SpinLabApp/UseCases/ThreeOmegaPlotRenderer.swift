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
    static let temperatureAxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .temperature, context: .plotAxis)
    static let deviceAngleAxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .deviceAngle, context: .plotAxis)

    static let r1AxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .plotAxis)
    static let r3AxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .plotAxis)
    static let rAHE1AxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .plotAxis)
    static let rAHE3AxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .plotAxis)
    static let hcAxisLabel = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .plotAxis, unit: .millitesla)
    static let rxxAxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .plotAxis)
    static let sigmaXXAxisLabel = ThreeOmegaDisplayScale.temperatureDependenceRightY.label(context: .plotAxis)
    static let eAHEOverE3AxisLabel = ThreeOmegaDisplayScale.temperatureDependenceLeftY.label(context: .plotAxis)
    static let rAHEAxisLabel = WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .plotAxis)

    static let scalingXAxisLabel = ThreeOmegaDisplayScale.scalingLawX.label(context: .plotAxis)
    static let scalingYAxisLabel = ThreeOmegaDisplayScale.scalingLawY.label(context: .plotAxis)

    // Temperature Dependence display transform — approved special-case convention
    // (docs/architecture/workbench/PLOT_DISPLAY_SPEC.md §4), permanently excluded from the
    // generic Display Standard the same way Scaling Law is. Scale factors and labels are
    // defined once in ThreeOmegaDisplayScaleSpec (see ThreeOmegaDisplayScaleSpec.swift).
    static let temperatureDependenceLeftYDisplayScale = ThreeOmegaDisplayScale.temperatureDependenceLeftY.scaleFactor
    static let temperatureDependenceRightYDisplayScale = ThreeOmegaDisplayScale.temperatureDependenceRightY.scaleFactor

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
    var tickOverride: PlotTickOverride? = nil
    var showPointTags: Bool = true
    /// Canonical visual series order (chip/legend top-to-bottom order). Passed straight
    /// through to WorkbenchRenderPipeline.Input.seriesOrder so the pipeline builds legend
    /// rows in chip order regardless of the renderer-internal stacking/draw order used to
    /// build the payload's series array.
    var canonicalVisualSeriesOrder: [String]? = nil

    private let defaultOptions = WorkbenchChartRenderer.Options()

    private enum RenderOutcome {
        case success(Data, Data, WorkbenchPlotLayout, [String])
        case failure(String)
    }

    private struct StackedFieldSweepPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
        let warnings: [String]
    }

    // MARK: - Individual tab renderers

    /// Tab 0: RAHE consolidated temperature view combining 1ω and 3ω curves.
    func makeRAHEPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        rahe1Method: ThreeOmegaV3Method = .highField,
        rahe3Method: ThreeOmegaV3Method = .highField
    ) -> WorkbenchPlotPayload? {
        makeCombinedRAHEVsTPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: [],
            rahe1Method: rahe1Method,
            rahe3Method: rahe3Method
        )?.manifestPayload
    }

    mutating func renderRAHE(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = [],
        rahe1Method: ThreeOmegaV3Method = .highField,
        rahe3Method: ThreeOmegaV3Method = .highField
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads = makeCombinedRAHEVsTPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys,
            rahe1Method: rahe1Method,
            rahe3Method: rahe3Method
        ) else {
            return (nil, nil, nil, nil, [])
        }
        var renderPayload = payloads.displayPayload
        var warnings: [String] = []
        let (data, pdf, layout) = _consume(_render(payload: &renderPayload), into: &warnings)
        warnings.append(contentsOf: payloads.warnings)
        return (data, pdf, layout, data != nil ? payloads.displayPayload : nil, warnings)
    }

    /// Tab 1: R(1ω) vs H, stacked by temperature
    func makeR1omegaPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        makeR1omegaPayloads(sweeps: sweeps, device: device, seriesOrder: seriesOrder, hiddenSeriesKeys: [])?.manifestPayload
    }

    /// Tab 2: R(3ω) vs H, stacked by temperature
    func makeR3omegaPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        makeR3omegaPayloads(sweeps: sweeps, device: device, seriesOrder: seriesOrder, hiddenSeriesKeys: [])?.manifestPayload
    }

    // MARK: - Payload-only construction (shared XY render route)
    //
    // Payload-construction logic for the field-sweep tabs, without invoking the pipeline.
    // Used by ThreeOmegaWorkspaceStore, which renders via TabRenderManager.buildPipelineInput
    // + WorkbenchRenderPipeline.render directly.

    func makeR1omegaDisplayPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (payload: WorkbenchPlotPayload, warnings: [String])? {
        guard let payloads = makeR1omegaPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        ) else {
            return nil
        }
        return (payloads.displayPayload, payloads.warnings)
    }

    func makeR3omegaDisplayPayload(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (payload: WorkbenchPlotPayload, warnings: [String])? {
        guard let payloads = makeR3omegaPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        ) else {
            return nil
        }
        return (payloads.displayPayload, payloads.warnings)
    }

    /// Dynamic chart height (scaled to sweep count) for stacked waterfall field-sweep
    /// plots — exposed statically so callers can build a `WorkbenchRenderPipeline.Input`
    /// without going through `_render`. Base 600px fits ~6 curves comfortably; each
    /// additional curve adds 40px.
    static func stackedOptions(
        sweepCount: Int,
        base: WorkbenchChartRenderer.Options = WorkbenchChartRenderer.Options()
    ) -> WorkbenchChartRenderer.Options {
        var opts = base
        opts.height = max(base.height, base.height + (sweepCount - 6) * 40)
        return opts
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

    private func makeCombinedRAHEVsTPayloads(
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String],
        rahe1Method: ThreeOmegaV3Method,
        rahe3Method: ThreeOmegaV3Method
    ) -> StackedFieldSweepPayloads? {
        guard !sweeps.isEmpty else { return nil }
        let temps1 = sweeps.compactMap { $0.rahe(harmonic: 1, method: rahe1Method) != nil ? $0.temperatureK : nil }
        let vals1  = sweeps.compactMap { $0.rahe(harmonic: 1, method: rahe1Method) }
        let temps3 = sweeps.compactMap { $0.rahe(harmonic: 3, method: rahe3Method) != nil ? $0.temperatureK : nil }
        let vals3  = sweeps.compactMap { $0.rahe(harmonic: 3, method: rahe3Method) }

        var rawSeries: [WorkbenchPlotSeries] = []
        if !temps1.isEmpty {
            rawSeries.append(WorkbenchPlotSeries(
                label: Self.rAHE1LegendLabel,
                x: temps1,
                y: vals1,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE,
                    seriesRole: "rahe-1omega",
                    stableSemanticID: "rahe-1omega"
                )
            ))
        }
        if !temps3.isEmpty {
            rawSeries.append(WorkbenchPlotSeries(
                label: Self.rAHE3LegendLabel,
                x: temps3,
                y: vals3,
                metadata: _seriesMetadata(
                    tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE,
                    seriesRole: "rahe-3omega",
                    stableSemanticID: "rahe-3omega"
                )
            ))
        }

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: rawSeries,
                visualSeriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys,
                stackingPolicy: .none
            )
        )

        let legendDimension = "Harmonic"

        let title = _defaultTitle("RAHE", device: device, deviceMode: _deviceMode(for: device))
        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: Self.rAHEAxisLabel),
            series: plan.visualSeries,
            legendDimension: legendDimension,
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: Self.rAHEAxisLabel),
            series: plan.displaySeries,
            legendDimension: legendDimension,
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        return StackedFieldSweepPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: plan.warnings
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
        let fieldUnit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(
            values: sweeps.flatMap(\.hField), sourceUnit: .tesla
        )
        let fieldAxisLabel = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(
            for: .externalMagneticField, context: .plotAxis, unit: fieldUnit
        )

        // Field-sweep stacked rendering must not order raw sweeps directly.
        // Build real WorkbenchPlotSeries with full identity metadata first, then
        // apply the visual order resolver to the actual series.
        let rawSeries = sweeps.map { sweep in
            let stableID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: sweep.stableSourceRef,
                sampleID: sweep.sampleID,
                fallback: sweep.device
            ) ?? sweep.device
            return WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: fieldUnit) },
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
        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: rawSeries,
                visualSeriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys,
                stackingPolicy: .orderEnforcingVertical(
                    multiplier: stackOffsetMultiplier,
                    minGapFraction: minGapFraction
                )
            )
        )

        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle(plotTitle, device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: fieldAxisLabel, yField: yAxisLabel),
            series: plan.visualSeries,
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "3w",
            title: _defaultTitle(plotTitle, device: device, deviceMode: _deviceMode(for: device)),
            axisMapping: WorkbenchAxisMapping(xField: fieldAxisLabel, yField: yAxisLabel),
            series: plan.displaySeries,
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        return StackedFieldSweepPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: plan.warnings
        )
    }

    /// Tab 3c: R_AHE(1ω) vs Device angle
    func makeRAHE1omegaVsDevicePayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        return _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: 1, device: device, method: method)
    }

    mutating func renderRAHE1omegaVsDevice(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEVsDevice(sweeps: sweeps, harmonic: 1, device: device, method: method)
    }

    /// Tab 3d: R_AHE(3ω) vs Device angle
    func makeRAHE3omegaVsDevicePayload(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> WorkbenchPlotPayload? {
        return _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: 3, device: device, method: method)
    }

    mutating func renderRAHE3omegaVsDevice(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        return _renderRAHEVsDevice(sweeps: sweeps, harmonic: 3, device: device, method: method)
    }

    /// Tab 3c/3d: diagnostic warnings for the RAHE-vs-Device payload accessors.
    /// Mixed temperatures make `_makeRAHEVsDevicePayload` return nil silently; this
    /// reproduces the same parse to explain why, so the runtime shared route and tests
    /// can observe the warning without going through the obsolete render entry points.
    func makeRAHE1omegaVsDeviceWarnings(sweeps: [ThreeOmegaFieldSweepResult], method: ThreeOmegaV3Method) -> [String] {
        _raheVsDeviceWarnings(sweeps: sweeps, harmonic: 1, method: method)
    }

    func makeRAHE3omegaVsDeviceWarnings(sweeps: [ThreeOmegaFieldSweepResult], method: ThreeOmegaV3Method) -> [String] {
        _raheVsDeviceWarnings(sweeps: sweeps, harmonic: 3, method: method)
    }

    private func _raheVsDeviceWarnings(
        sweeps: [ThreeOmegaFieldSweepResult],
        harmonic: Int,
        method: ThreeOmegaV3Method
    ) -> [String] {
        let parsed = sweeps.compactMap { sweep -> Double? in
            guard ThreeOmegaDeviceAngleParser.parseDegrees(sweep.device) != nil,
                  sweep.rahe(harmonic: harmonic, method: method) != nil else { return nil }
            return sweep.temperatureK
        }
        guard Set(parsed).count > 1 else { return [] }
        let hLabel = harmonic == 1 ? "1ω" : "3ω"
        return ["R_AHE(\(hLabel)) vs Device: mixed temperatures detected — chart requires a single temperature. Select sweeps from one temperature only."]
    }

    private mutating func _renderRAHEVsDevice(
        sweeps: [ThreeOmegaFieldSweepResult],
        harmonic: Int,
        device: String,
        method: ThreeOmegaV3Method
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = _makeRAHEVsDevicePayload(sweeps: sweeps, harmonic: harmonic, device: device, method: method) else {
            return (nil, nil, nil, nil, _raheVsDeviceWarnings(sweeps: sweeps, harmonic: harmonic, method: method))
        }
        let displayPayload = payload
        var mutablePayload = payload
        var w: [String] = []
        let (data, pdf, layout) = _consume(_render(payload: &mutablePayload), into: &w)
        return (data, pdf, layout, data != nil ? displayPayload : nil, w)
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

    /// Tab 4: Hc¹ω and Hc³ω vs T
    func makeHcPayload(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> WorkbenchPlotPayload? {
        let hcUnit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(
            values: sweeps.compactMap(\.hc1omega) + sweeps.compactMap(\.hc3omega), sourceUnit: .tesla
        )
        let hcAxisLabel = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(
            for: .coerciveField, context: .plotAxis, unit: hcUnit
        )
        let temps1 = sweeps.compactMap { $0.hc1omega != nil ? $0.temperatureK : nil }
        let hc1    = sweeps.compactMap { $0.hc1omega }.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: hcUnit) }
        let temps3 = sweeps.compactMap { $0.hc3omega != nil ? $0.temperatureK : nil }
        let hc3    = sweeps.compactMap { $0.hc3omega }.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: hcUnit) }
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
            axisMapping: WorkbenchAxisMapping(xField: Self.temperatureAxisLabel, yField: hcAxisLabel),
            series: series
        )
    }

    mutating func renderHcVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeHcPayload(sweeps: sweeps, device: device) else {
            return (nil, nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, pdf, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, pdf, layout, data != nil ? displayPayload : nil, w)
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

    mutating func renderRT(rt: ThreeOmegaRTResult) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeRTPayload(rt: rt) else { return (nil, nil, nil, nil, []) }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, pdf, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, pdf, layout, data != nil ? displayPayload : nil, w)
    }

    /// Tab 6: Fig 5b — E^(3ω)_AHE / (E_xx³ × σ_xx) vs σ²_xx
    /// Display units: X in 10⁷ S²/cm², Y in Ω·μm³·V⁻²
    /// Conversions: X_SI (S/m)² × 1e-11 → 10⁷ S²/cm²
    ///              Y_SI (Ω·m³/V²) × 1e20 → Ω·μm³·V⁻² × 10²
    mutating func renderScaling(result: ThreeOmegaScalingResult, device: String = "", method: String = "") -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeScalingPayload(result: result, device: device, method: method) else {
            return (nil, nil, nil, nil, [])
        }
        let displayPayload = payload
        var renderPayload = payload
        var w: [String] = []
        let (data, pdf, layout) = _consume(_render(payload: &renderPayload), into: &w)
        return (data, pdf, layout, data != nil ? displayPayload : nil, w)
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
        let leftY = seriesPoints.map { $0.leftY * Self.temperatureDependenceLeftYDisplayScale }
        let rightY = seriesPoints.map { $0.sigmaXX * Self.temperatureDependenceRightYDisplayScale }

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

        let xScale = ThreeOmegaDisplayScale.scalingLawX.scaleFactor
        let yScale = ThreeOmegaDisplayScale.scalingLawY.scaleFactor
        let xs = result.points.map { $0.sigma2xx * xScale }   // (S/m)² → 10⁷ S²/cm²
        let ys = result.points.map { $0.scalingY  * yScale }  // Ω·m³/V² → Ω·μm³·V⁻² × 10²
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
            let alphaD = segment.alpha * ThreeOmegaDisplayScale.scalingLawFitSlope.scaleFactor
            let betaD  = segment.beta  * yScale

            // Compute fit line range using perpendicular projection of each data point
            // onto the line y = alphaD * x + betaD.
            // Foot x-coordinate: x_foot = (xi + alphaD * (yi - betaD)) / (1 + alphaD²)
            let denom = 1.0 + alphaD * alphaD
            let segPointIndices = result.points.enumerated().compactMap { i, pt in
                segment.participatingXValues.contains(pt.sigma2xx) ? i : nil
            }
            let footXs: [Double] = segPointIndices.map { i in
                let xi = result.points[i].sigma2xx * xScale
                let yi = result.points[i].scalingY * yScale
                return (xi + alphaD * (yi - betaD)) / denom
            }
            let x0 = footXs.min() ?? (segment.participatingXValues.min() ?? 0) * xScale
            let x1 = footXs.max() ?? (segment.participatingXValues.max() ?? 0) * xScale
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
            series: series,
            styleParams: ["defaultPointTagsVisible": "true"]
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

        var input = WorkbenchRenderPipeline.Input(
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
            seriesOrder: canonicalVisualSeriesOrder,
            axisRangeOverride: axisRangeOverride,
            tickOverride: tickOverride,
            showPointTags: showPointTags
        )
        input.pixelScaleOverride = WorkbenchPlotRenderScale.display
        do {
            let output = try WorkbenchRenderPipeline.render(input)
            payload = output.manifestPayload
            return .success(output.imageData, output.pdfData, output.layout, output.warnings)
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

    private func _consume(_ outcome: RenderOutcome, into warnings: inout [String]) -> (Data?, Data?, WorkbenchPlotLayout?) {
        switch outcome {
        case .success(let imageData, let pdfData, let layout, let w):
            warnings.append(contentsOf: w)
            return (imageData, pdfData, layout)
        case .failure(let reason):
            warnings.append(reason)
            return (nil, nil, nil)
        }
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
