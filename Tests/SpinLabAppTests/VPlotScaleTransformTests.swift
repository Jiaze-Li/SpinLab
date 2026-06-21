import Testing
@testable import SpinLabApp

@Suite("PlotScaleTransform")
struct PlotScaleTransformTests {

    @Test("PlotScaleTransform linear normalization works")
    func linearNormalizationWorks() {
        let transform = PlotScaleTransform.linear
        #expect(abs(transform.normalizedValue(for: 0, lowerBound: 0, upperBound: 10) - 0) < 1e-12)
        #expect(abs(transform.normalizedValue(for: 5, lowerBound: 0, upperBound: 10) - 0.5) < 1e-12)
        #expect(abs(transform.normalizedValue(for: 10, lowerBound: 0, upperBound: 10) - 1) < 1e-12)
    }

    @Test("PlotScaleTransform log10 normalization works")
    func log10NormalizationWorks() {
        let transform = PlotScaleTransform.log10
        #expect(abs(transform.normalizedValue(for: 1, lowerBound: 1, upperBound: 100) - 0) < 1e-12)
        #expect(abs(transform.normalizedValue(for: 10, lowerBound: 1, upperBound: 100) - 0.5) < 0.05)
        #expect(abs(transform.normalizedValue(for: 100, lowerBound: 1, upperBound: 100) - 1) < 1e-12)
    }

    @Test("PlotScaleTransform log10 handles zero safely")
    func log10HandlesZeroSafely() {
        let transform = PlotScaleTransform.log10
        let value = transform.normalizedValue(for: 0, lowerBound: 0, upperBound: 100)
        #expect(value == 0)
        #expect(!value.isNaN)
        #expect(value.isFinite)
    }

    @Test("PlotScaleTransform log10 handles negative values safely")
    func log10HandlesNegativeValuesSafely() {
        let transform = PlotScaleTransform.log10
        let value = transform.normalizedValue(for: -25, lowerBound: -25, upperBound: 100)
        #expect(value == 0)
        #expect(!value.isNaN)
        #expect(value.isFinite)
    }

    @Test("PlotScaleTransform handles NaN safely")
    func handlesNaNSafely() {
        for transform in [PlotScaleTransform.linear, .log10] {
            let value = transform.normalizedValue(for: .nan, lowerBound: 0, upperBound: 10)
            #expect(value == 0)
            #expect(!value.isNaN)
            #expect(value.isFinite)
        }
    }

    @Test("PlotScaleTransform handles +Inf and -Inf safely")
    func handlesInfinitySafely() {
        for transform in [PlotScaleTransform.linear, .log10] {
            let positive = transform.normalizedValue(for: .infinity, lowerBound: 0, upperBound: 10)
            let negative = transform.normalizedValue(for: -.infinity, lowerBound: 0, upperBound: 10)
            #expect(positive == 1)
            #expect(negative == 0)
            #expect(positive.isFinite)
            #expect(negative.isFinite)
        }
    }

    @Test("PlotScaleTransform never returns NaN or Inf")
    func neverReturnsNaNOrInf() {
        let values: [Double] = [.nan, -.infinity, -100, 0, 1, 10, .infinity]
        for transform in [PlotScaleTransform.linear, .log10] {
            for value in values {
                let normalized = transform.normalizedValue(for: value, lowerBound: 0, upperBound: 10)
                #expect(normalized.isFinite)
                #expect(!normalized.isNaN)
                #expect(normalized >= 0)
                #expect(normalized <= 1)
            }
        }
    }
}
