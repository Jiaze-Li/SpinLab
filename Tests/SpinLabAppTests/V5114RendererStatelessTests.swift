import Testing
import Foundation
@testable import SpinLabApp

@Suite("V5.1.14 Renderer Stateless")
struct V5114RendererStatelessTests {

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
