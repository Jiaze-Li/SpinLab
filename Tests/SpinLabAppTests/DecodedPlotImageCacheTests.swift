import AppKit
import Testing
@testable import SpinLabApp

@Suite("Decoded Plot Image Cache Tests")
struct DecodedPlotImageCacheTests {

    private func png(width: Int, height: Int, gray: UInt8) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        if let base = rep.bitmapData {
            for i in 0..<(rep.bytesPerRow * height) { base[i] = gray }
        }
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("same PNG content reuses the decoded image, even via a distinct Data value")
    func reusesForSameContent() {
        let cache = DecodedPlotImageCache()
        let a = png(width: 40, height: 30, gray: 200)
        let first = cache.image(for: a)
        let second = cache.image(for: a)
        let third = cache.image(for: Data(a))
        #expect(first != nil)
        #expect(first === second)
        #expect(first === third)
        #expect(cache.decodeCount == 1)
    }

    @Test("different content with identical dimensions and byte count is not reused")
    func sameSizeDifferentContent() {
        let cache = DecodedPlotImageCache()
        let a = png(width: 40, height: 30, gray: 200)
        var b = a
        // Flip one byte inside the compressed stream region while keeping length equal.
        b[b.count / 2] ^= 0xFF
        #expect(a.count == b.count)
        let first = cache.image(for: a)
        let second = cache.image(for: b)
        #expect(cache.decodeCount == 2)
        #expect(first !== second)
    }

    @Test("new PNG replaces the cached image and returns to old content decodes again")
    func newPNGUpdates() {
        let cache = DecodedPlotImageCache()
        let a = png(width: 40, height: 30, gray: 10)
        let b = png(width: 60, height: 20, gray: 240)
        let imageA = cache.image(for: a)
        let imageB = cache.image(for: b)
        #expect(imageB?.size.width == 60)
        #expect(imageA !== imageB)
        #expect(cache.image(for: a)?.size.width == 40)
        #expect(cache.decodeCount == 3)
    }

    @Test("clearing the plot drops the image; restoring decodes fresh")
    func clearAndRestore() {
        let cache = DecodedPlotImageCache()
        let a = png(width: 40, height: 30, gray: 90)
        _ = cache.image(for: a)
        #expect(cache.image(for: nil) == nil)
        #expect(cache.image(for: a) != nil)
        #expect(cache.decodeCount == 2)
    }

    @Test("undecodable data yields nil and is not cached as valid")
    func undecodable() {
        let cache = DecodedPlotImageCache()
        let junk = Data([1, 2, 3, 4])
        #expect(cache.image(for: junk) == nil)
        #expect(cache.image(for: junk) == nil)
        #expect(cache.decodeCount == 2)
    }
}
