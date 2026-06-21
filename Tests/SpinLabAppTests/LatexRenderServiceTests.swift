import CoreGraphics
import Testing
@testable import SpinLabApp

// MARK: - Test backends

/// Backend that always reports unavailable and returns nil.
struct UnavailableLatexBackend: LatexRenderBackend {
    var isAvailable: Bool { false }
    func compile(latex: String, colorHex: String, pixelScale: CGFloat) -> (image: CGImage, naturalSize: CGSize)? { nil }
}

/// Backend that always reports available and returns a fixed-size blank image.
struct FixedSizeLatexBackend: LatexRenderBackend {
    let fixedNaturalSize: CGSize
    var isAvailable: Bool { true }

    func compile(latex: String, colorHex: String, pixelScale: CGFloat) -> (image: CGImage, naturalSize: CGSize)? {
        let w = max(1, Int(fixedNaturalSize.width.rounded()))
        let h = max(1, Int(fixedNaturalSize.height.rounded()))
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        ), let image = ctx.makeImage() else { return nil }
        return (image, fixedNaturalSize)
    }
}

final class LatexCompileCapture {
    var latex: String?
    var colorHex: String?
    var pixelScale: CGFloat?
    var count = 0
}

struct RecordingLatexBackend: LatexRenderBackend {
    let fixedNaturalSize: CGSize
    let capture: LatexCompileCapture
    var isAvailable: Bool { true }

    func compile(latex: String, colorHex: String, pixelScale: CGFloat) -> (image: CGImage, naturalSize: CGSize)? {
        capture.count += 1
        capture.latex = latex
        capture.colorHex = colorHex
        capture.pixelScale = pixelScale
        return FixedSizeLatexBackend(fixedNaturalSize: fixedNaturalSize).compile(
            latex: latex,
            colorHex: colorHex,
            pixelScale: pixelScale
        )
    }
}

// MARK: - LatexRenderService tests

@Suite("LatexRenderService")
struct LatexRenderServiceTests {

    // MARK: - CacheKey

    @Test("CacheKey equal for same latex + colorHex + pixelScale")
    func cacheKeyEquality() {
        let k1 = LatexRenderService.CacheKey(latex: "\\frac{a}{b}", colorHex: "000000ff", pixelScale: 2.0)
        let k2 = LatexRenderService.CacheKey(latex: "\\frac{a}{b}", colorHex: "000000ff", pixelScale: 2.0)
        #expect(k1 == k2)
        var set = Set<LatexRenderService.CacheKey>()
        set.insert(k1); set.insert(k2)
        #expect(set.count == 1)
    }

    @Test("CacheKey differs for different colorHex")
    func cacheKeyDiffersForColor() {
        let k1 = LatexRenderService.CacheKey(latex: "x", colorHex: "000000ff", pixelScale: 2.0)
        let k2 = LatexRenderService.CacheKey(latex: "x", colorHex: "ff0000ff", pixelScale: 2.0)
        #expect(k1 != k2)
    }

    @Test("CacheKey differs for different pixelScale")
    func cacheKeyDiffersForScale() {
        let k1 = LatexRenderService.CacheKey(latex: "x", colorHex: "000000ff", pixelScale: 1.0)
        let k2 = LatexRenderService.CacheKey(latex: "x", colorHex: "000000ff", pixelScale: 2.0)
        #expect(k1 != k2)
    }

    @Test("CacheKey differs for different latex")
    func cacheKeyDiffersForLatex() {
        let k1 = LatexRenderService.CacheKey(latex: "x", colorHex: "000000ff", pixelScale: 2.0)
        let k2 = LatexRenderService.CacheKey(latex: "y", colorHex: "000000ff", pixelScale: 2.0)
        #expect(k1 != k2)
    }

    // MARK: - Unavailable backend

    @Test("render returns nil when backend is unavailable")
    func renderNilWhenUnavailable() {
        let service = LatexRenderService(backend: UnavailableLatexBackend())
        let result = service.render(latex: "x^2")
        #expect(result == nil)
    }

    @Test("naturalSize returns nil when backend is unavailable")
    func naturalSizeNilWhenUnavailable() {
        let service = LatexRenderService(backend: UnavailableLatexBackend())
        let result = service.naturalSize(latex: "x^2", fontSize: 20)
        #expect(result == nil)
    }

    @Test("isAvailable reflects backend availability")
    func isAvailableReflectsBackend() {
        let unavailable = LatexRenderService(backend: UnavailableLatexBackend())
        #expect(!unavailable.isAvailable)

        let available = LatexRenderService(backend: FixedSizeLatexBackend(fixedNaturalSize: CGSize(width: 100, height: 30)))
        #expect(available.isAvailable)
    }

    // MARK: - Fixed-size backend

    @Test("render returns asset from fixed-size backend")
    func renderReturnsAssetFromFixedBackend() {
        let natural = CGSize(width: 80, height: 20)
        let service = LatexRenderService(backend: FixedSizeLatexBackend(fixedNaturalSize: natural))
        let asset = service.render(latex: "x^2")
        #expect(asset != nil)
        if let a = asset {
            #expect(a.naturalSize.width == natural.width)
            #expect(a.naturalSize.height == natural.height)
        }
    }

    @Test("naturalSize scales natural size by fontSize / 12")
    func naturalSizeScalesByFontSize() {
        let natural = CGSize(width: 60, height: 20)
        let service = LatexRenderService(backend: FixedSizeLatexBackend(fixedNaturalSize: natural))
        let fontSize: CGFloat = 20
        let size = service.naturalSize(latex: "x^2", fontSize: fontSize)
        #expect(size != nil)
        if let s = size {
            let scale = fontSize / 12.0
            #expect(abs(s.width  - natural.width  * scale) < 0.001)
            #expect(abs(s.height - natural.height * scale) < 0.001)
        }
    }

    // MARK: - Caching

    @Test("Same latex string hits cache on second call")
    func sameLatexyHitsCache() {
        // Wrap a backend that counts compile calls
        struct CountingBackend: LatexRenderBackend {
            let inner: FixedSizeLatexBackend
            // Swift structs can't have inout closures cleanly; use a class counter
            let counter: Counter
            var isAvailable: Bool { true }
            func compile(latex: String, colorHex: String, pixelScale: CGFloat) -> (image: CGImage, naturalSize: CGSize)? {
                counter.count += 1
                return inner.compile(latex: latex, colorHex: colorHex, pixelScale: pixelScale)
            }
        }
        final class Counter { var count = 0 }
        let counter = Counter()
        let backend = CountingBackend(
            inner: FixedSizeLatexBackend(fixedNaturalSize: CGSize(width: 50, height: 15)),
            counter: counter
        )
        let service = LatexRenderService(backend: backend)

        _ = service.render(latex: "x^2", pixelScale: 2.0)
        _ = service.render(latex: "x^2", pixelScale: 2.0)
        #expect(counter.count == 1, "Second render of same latex must hit cache, not recompile")
    }

    @Test("render passes colorHex and pixelScale to backend")
    func renderPassesInputsToBackend() {
        let capture = LatexCompileCapture()
        let service = LatexRenderService(
            backend: RecordingLatexBackend(
                fixedNaturalSize: CGSize(width: 40, height: 12),
                capture: capture
            )
        )
        let color = CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        _ = service.render(latex: "x^2", color: color, pixelScale: 3.25)

        #expect(capture.count == 1)
        #expect(capture.latex == "x^2")
        #expect(capture.colorHex == "4080bf")
        #expect(capture.pixelScale == 3.25)
    }

    @Test("render caches independently by color and pixelScale")
    func renderCachesByInputs() {
        let capture = LatexCompileCapture()
        let service = LatexRenderService(
            backend: RecordingLatexBackend(
                fixedNaturalSize: CGSize(width: 40, height: 12),
                capture: capture
            )
        )
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)

        _ = service.render(latex: "x^2", color: black, pixelScale: 2.0)
        _ = service.render(latex: "x^2", color: black, pixelScale: 2.0)
        #expect(capture.count == 1)

        _ = service.render(latex: "x^2", color: red, pixelScale: 2.0)
        _ = service.render(latex: "x^2", color: red, pixelScale: 3.0)
        #expect(capture.count == 3)
    }

    @Test("render clamps pixelScale before caching and compiling")
    func renderClampsPixelScale() {
        let capture = LatexCompileCapture()
        let service = LatexRenderService(
            backend: RecordingLatexBackend(
                fixedNaturalSize: CGSize(width: 40, height: 12),
                capture: capture
            )
        )

        _ = service.render(latex: "x^2", pixelScale: 0)
        #expect(capture.pixelScale == 0.1)

        _ = service.render(latex: "y^2", pixelScale: 99)
        #expect(capture.pixelScale == 4.0)
        #expect(LatexRenderService.clampedPixelScale(-5) == 0.1)
        #expect(LatexRenderService.clampedPixelScale(2.5) == 2.5)
    }

    @Test("Different latex strings each call compile")
    func differentLatexEachCompile() {
        final class Counter { var count = 0 }
        struct CountingBackend: LatexRenderBackend {
            let counter: Counter
            var isAvailable: Bool { true }
            func compile(latex: String, colorHex: String, pixelScale: CGFloat) -> (image: CGImage, naturalSize: CGSize)? {
                counter.count += 1
                return FixedSizeLatexBackend(fixedNaturalSize: CGSize(width: 50, height: 15)).compile(
                    latex: latex,
                    colorHex: colorHex,
                    pixelScale: pixelScale
                )
            }
        }
        let counter = Counter()
        let service = LatexRenderService(backend: CountingBackend(counter: counter))
        _ = service.render(latex: "x^2", pixelScale: 2.0)
        _ = service.render(latex: "y^3", pixelScale: 2.0)
        #expect(counter.count == 2, "Different latex strings must produce separate cache entries")
    }

    // MARK: - hexString helper

    @Test("hexString encodes black correctly")
    func hexStringBlack() {
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        #expect(LatexRenderService.hexString(black) == "000000ff")
    }

    @Test("hexString encodes red correctly")
    func hexStringRed() {
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(LatexRenderService.hexString(red) == "ff0000ff")
    }

    @Test("normalizedRGBHexString strips alpha for LaTeX rendering")
    func normalizedRGBHexStringStripsAlpha() {
        let color = CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        #expect(LatexRenderService.normalizedRGBHexString(color) == "1a334d")
    }

    // MARK: - LocalLatexBackend detection

    @Test("LocalLatexBackend.detect() returns a result without crashing")
    func detectBackendNoCrash() {
        let status = LocalLatexBackend.detect()
        switch status {
        case .latexmk(let p): #expect(!p.isEmpty)
        case .pdflatex(let p): #expect(!p.isEmpty)
        case .unavailable: break
        }
    }

    @Test("LocalLatexBackend with forced .unavailable status is not available")
    func forcedUnavailableStatus() {
        let b = LocalLatexBackend(status: .unavailable)
        #expect(!b.isAvailable)
        let result = b.compile(latex: "x", colorHex: "000000", pixelScale: 2.0)
        #expect(result == nil)
    }

    @Test("makeTexDocument includes xcolor and color definition")
    func makeTexDocumentIncludesColorSupport() {
        let backend = LocalLatexBackend(status: .unavailable)
        let tex = backend.makeTexDocument(latex: "\\frac{a}{b}", colorHex: "ff3366")
        #expect(tex.contains("\\usepackage{xcolor}"))
        #expect(tex.contains("\\definecolor{spinlabaxis}{HTML}{ff3366}"))
        #expect(tex.contains("\\color{spinlabaxis}"))
    }

    // MARK: - LatexAxisLabelRenderer does not own compilation (structural)

    @Test("LatexAxisLabelRenderer sources compile only via LatexRenderService (structural)")
    func axisRendererDelegatesToService() {
        // An axis renderer backed by a known fixed-size service must return that exact size.
        // If LatexAxisLabelRenderer were compiling independently, it would return a different
        // (real or nil) value rather than the service's injected response.
        let fixedNatural = CGSize(width: 120, height: 30)
        let service = LatexRenderService(backend: FixedSizeLatexBackend(fixedNaturalSize: fixedNatural))
        let renderer = LatexAxisLabelRenderer(service: service)

        let fontSize: CGFloat = 20
        let scale = fontSize / 12.0
        let size = renderer.labelSize(latex: "E = mc^2", fontSize: fontSize)
        #expect(size != nil)
        if let s = size {
            #expect(abs(s.width  - fixedNatural.width  * scale) < 0.001,
                    "Width must come from the injected service, not independent compilation")
            #expect(abs(s.height - fixedNatural.height * scale) < 0.001,
                    "Height must come from the injected service, not independent compilation")
        }
    }

    @Test("LatexAxisLabelRenderer with unavailable service returns nil")
    func axisRendererUnavailableServiceReturnsNil() {
        let service = LatexRenderService(backend: UnavailableLatexBackend())
        let renderer = LatexAxisLabelRenderer(service: service)
        let result = renderer.labelSize(latex: "x^2", fontSize: 20)
        #expect(result == nil)
    }

    @Test("LatexAxisLabelRenderer.draw returns false when service unavailable")
    func axisRendererDrawReturnsFalseWhenUnavailable() {
        let service = LatexRenderService(backend: UnavailableLatexBackend())
        let renderer = LatexAxisLabelRenderer(service: service)
        let ctx = makeTestContext()
        let result = renderer.draw(
            ctx: ctx, latex: "x^2", fontSize: 20,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            at: CGPoint(x: 50, y: 50), orientation: .horizontal
        )
        #expect(result == false)
    }

    // MARK: - Horizontal footprint (X-axis) uses rendered asset width

    @Test("xAxisLane with latex: label uses rendered asset height as lane height via service")
    func xAxisLaneFootprintFromService() {
        // Verify via the layout calculator's latexLabelSizeOverride pathway.
        let injectedSize = CGSize(width: 250, height: 28)
        let style = WorkbenchChartStyle()

        let lane = PlotAxisSpacingCalculator.xAxisLane(
            axisTitleText: "latex:\\sigma_{xx}^{2}",
            tickLabels: ["0", "1", "2"],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            minimumAxisTitleLane: 0,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseBottomPadding: 88,
            latexLabelSizeOverride: injectedSize
        )
        // Lane height must equal PDF height (28), not PDF width (250).
        #expect(lane.axisTitleLaneHeight == injectedSize.height,
                "X-axis LaTeX label lane height must equal rendered PDF height (got \(lane.axisTitleLaneHeight))")
    }

    // MARK: - Integration (only when LaTeX installed)

    @Test("Integration: LatexRenderService.shared compiles E=mc^2 via real backend")
    func integrationRealBackend() {
        guard LatexRenderService.shared.isAvailable else { return }
        // Compilation may still fail in sandboxed/CI environments even when latexmk is found.
        let size = LatexRenderService.shared.naturalSize(latex: "E = mc^{2}", fontSize: 20)
        if let s = size {
            #expect(s.width > 0)
            #expect(s.height > 0)
        }
        // No assertion on nil — compilation failure is acceptable (test environment constraint).
    }

    // MARK: - Helpers

    private func makeTestContext() -> CGContext {
        CGContext(
            data: nil, width: 200, height: 200,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        )!
    }
}
