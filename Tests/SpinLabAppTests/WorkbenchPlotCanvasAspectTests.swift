import CoreGraphics
import Testing
@testable import SpinLabApp

@Suite("Workbench Plot Canvas Aspect Ratio Tests")
struct WorkbenchPlotCanvasAspectTests {

    @Test("displayRect preserves aspect ratio for landscape image in normal container")
    func landscapeNormalContainer() {
        let imageSize = CGSize(width: 800, height: 600) // 4:3
        let containerSize = CGSize(width: 800, height: 600)
        let rect = WorkbenchPlotCanvas.displayRect(imageSize: imageSize, containerSize: containerSize)

        #expect(rect.width == 800)
        #expect(rect.height == 600)
        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 0)
        #expect(abs((rect.width / rect.height) - (imageSize.width / imageSize.height)) < 0.001)
    }

    @Test("displayRect preserves aspect ratio for landscape image in narrow container with minHeight clamping")
    func landscapeNarrowContainerWithMinHeight() {
        // e.g. Container width is 400, but minHeight is 360.
        // Proportional height for 4:3 image with width 400 is 300.
        // Previously, the image was stretched to 400x360 (scaleX != scaleY).
        let imageSize = CGSize(width: 800, height: 600) // 4:3
        let containerSize = CGSize(width: 400, height: 360)
        let rect = WorkbenchPlotCanvas.displayRect(imageSize: imageSize, containerSize: containerSize)

        #expect(rect.width == 400)
        #expect(rect.height == 300)
        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 30) // (360 - 300) / 2 = 30, centered vertically
        #expect(abs((rect.width / rect.height) - (imageSize.width / imageSize.height)) < 0.001)

        // Verify scaleX == scaleY
        let scaleX = rect.width / imageSize.width // 400 / 800 = 0.5
        let scaleY = rect.height / imageSize.height // 300 / 600 = 0.5
        #expect(abs(scaleX - scaleY) < 0.0001)
    }

    @Test("displayRect preserves aspect ratio for portrait image")
    func portraitContainer() {
        let imageSize = CGSize(width: 600, height: 900) // 2:3
        let containerSize = CGSize(width: 400, height: 600)
        let rect = WorkbenchPlotCanvas.displayRect(imageSize: imageSize, containerSize: containerSize)

        #expect(rect.width == 400)
        #expect(abs(rect.height - 600) < 0.001)
        #expect(abs((rect.width / rect.height) - (imageSize.width / imageSize.height)) < 0.001)

        let scaleX = rect.width / imageSize.width
        let scaleY = rect.height / imageSize.height
        #expect(abs(scaleX - scaleY) < 0.0001)
    }

    @Test("displayRect preserves aspect ratio for square image in narrow container")
    func squareImageNarrowContainer() {
        let imageSize = CGSize(width: 500, height: 500) // 1:1
        let containerSize = CGSize(width: 300, height: 360)
        let rect = WorkbenchPlotCanvas.displayRect(imageSize: imageSize, containerSize: containerSize)

        #expect(rect.width == 300)
        #expect(rect.height == 300)
        #expect(rect.origin.y == 30) // (360 - 300) / 2
        #expect(abs((rect.width / rect.height) - 1.0) < 0.001)

        let scaleX = rect.width / imageSize.width
        let scaleY = rect.height / imageSize.height
        #expect(abs(scaleX - scaleY) < 0.0001)
    }

    @Test("CoordinateContext with displayRect produces uniform scaleX and scaleY")
    func coordinateContextScaleUniformity() {
        let imageSize = CGSize(width: 800, height: 600)
        let containerSize = CGSize(width: 400, height: 360)
        let displayRect = WorkbenchPlotCanvas.displayRect(imageSize: imageSize, containerSize: containerSize)
        let context = CoordinateContext(rendererSize: imageSize, displayRect: displayRect)

        let scaleX = context.displayRect.width / context.rendererSize.width
        let scaleY = context.displayRect.height / context.rendererSize.height
        #expect(abs(scaleX - scaleY) < 0.0001)

        // Point mapping verification
        let centerPoint = CGPoint(x: 400, y: 300)
        let screenPoint = context.rendererToScreen(centerPoint)
        #expect(abs(screenPoint.x - 200) < 0.001)
        #expect(abs(screenPoint.y - (30 + 150)) < 0.001) // Y is inverted from bottom-left origin in renderer to top-left screen
    }
}
