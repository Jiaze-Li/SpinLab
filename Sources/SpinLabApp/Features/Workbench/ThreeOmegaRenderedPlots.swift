import Foundation

struct ThreeOmegaRenderedPlots: Sendable {
    var ahe:                  Data?
    var r1omega:              Data?
    var r3omega:              Data?
    var rahe1omegaVsT:        Data?
    var rahe3omegaVsT:        Data?
    var rahe1omegaVsDevice:   Data?
    var rahe3omegaVsDevice:   Data?
    var hcVsT:                Data?
    var rtCurve:              Data?
    var scaling:              Data?
    // Layouts for interactive WorkbenchPlotCanvas
    var layoutAHE:                  WorkbenchPlotLayout?
    var layoutR1omega:              WorkbenchPlotLayout?
    var layoutR3omega:              WorkbenchPlotLayout?
    var layoutRAHE1omegaVsT:        WorkbenchPlotLayout?
    var layoutRAHE3omegaVsT:        WorkbenchPlotLayout?
    var layoutRAHE1omegaVsDevice:   WorkbenchPlotLayout?
    var layoutRAHE3omegaVsDevice:   WorkbenchPlotLayout?
    var layoutHcVsT:                WorkbenchPlotLayout?
    var layoutRTCurve:              WorkbenchPlotLayout?
    var layoutScaling:              WorkbenchPlotLayout?
    var pipelineWarnings:           [String] = []
    // Display-faithful payloads for Copy PNG export (offset/stacked y-values applied, real data)
    var displayAHE:                 WorkbenchPlotPayload?
    var displayR1omega:             WorkbenchPlotPayload?
    var displayR3omega:             WorkbenchPlotPayload?
    var displayRAHE1omegaVsT:       WorkbenchPlotPayload?
    var displayRAHE3omegaVsT:       WorkbenchPlotPayload?
    var displayRAHE1omegaVsDevice:  WorkbenchPlotPayload?
    var displayRAHE3omegaVsDevice:  WorkbenchPlotPayload?
    var displayHcVsT:               WorkbenchPlotPayload?
    var displayRTCurve:             WorkbenchPlotPayload?
    var displayScaling:             WorkbenchPlotPayload?
}
