import Foundation

struct ThreeOmegaRenderedPlots: Sendable {
    var rahe:                 Data?
    var r1omega:              Data?
    var r3omega:              Data?
    var rahe1omegaVsDevice:   Data?
    var rahe3omegaVsDevice:   Data?
    var hcVsT:                Data?
    var rtCurve:              Data?
    var scaling:              Data?
    // Layouts for interactive WorkbenchPlotCanvas
    var layoutRAHE:                 WorkbenchPlotLayout?
    var layoutR1omega:              WorkbenchPlotLayout?
    var layoutR3omega:              WorkbenchPlotLayout?
    var layoutRAHE1omegaVsDevice:   WorkbenchPlotLayout?
    var layoutRAHE3omegaVsDevice:   WorkbenchPlotLayout?
    var layoutHcVsT:                WorkbenchPlotLayout?
    var layoutRTCurve:              WorkbenchPlotLayout?
    var layoutScaling:              WorkbenchPlotLayout?
    var pipelineWarnings:           [String] = []
    // Display-faithful payloads for Copy PNG export (offset/stacked y-values applied, real data)
    var displayRAHE:                WorkbenchPlotPayload?
    var displayR1omega:             WorkbenchPlotPayload?
    var displayR3omega:             WorkbenchPlotPayload?
    var displayRAHE1omegaVsDevice:  WorkbenchPlotPayload?
    var displayRAHE3omegaVsDevice:  WorkbenchPlotPayload?
    var displayHcVsT:               WorkbenchPlotPayload?
    var displayRTCurve:             WorkbenchPlotPayload?
    var displayScaling:             WorkbenchPlotPayload?
}
