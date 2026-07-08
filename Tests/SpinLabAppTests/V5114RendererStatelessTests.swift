import Testing
import Foundation
@testable import SpinLabApp

@Suite("V5.1.14 Renderer Stateless")
struct V5114RendererStatelessTests {

    // INV-5: Two consecutive renderR1omega calls on the same renderer instance
    // produce independent warning lists — no cross-call contamination.
    @Test("INV-5a: consecutive ThreeOmegaPlotRenderer calls have independent warnings")
    func threeOmegaRendererIsStateless() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps: [ThreeOmegaFieldSweepResult] = []
        let first  = r.renderR1omega(sweeps: sweeps, device: "D")
        let second = r.renderR1omega(sweeps: sweeps, device: "D")
        #expect(first.4.count == second.4.count,
                "consecutive renders must not share warning state; counts must match independently")
    }

    // INV-5b: Two consecutive renderRxxVsPhi calls on the same renderer instance
    // produce independent warning lists.
    @Test("INV-5b: consecutive XYRotationPlotRenderer calls have independent warnings")
    func xyRotationRendererIsStateless() {
        var r = XYRotationPlotRenderer()
        let sweeps: [XYRotationAngleSweep] = []
        let first  = r.renderRxxVsPhi(sweeps: sweeps, device: "D")
        let second = r.renderRxxVsPhi(sweeps: sweeps, device: "D")
        #expect(first.4.count == second.4.count,
                "consecutive renders must not share warning state; counts must match independently")
    }
}
