import Foundation
import Testing
@testable import SpinLabApp

@Suite("IBWReader")
struct IBWReaderTests {

    private func makeHeightOnlyFixture(nX: Int = 3, nY: Int = 2, xScale: Double = 1e-7, yScale: Double = 1e-7) -> Data {
        let values = (0..<nY).map { y in (0..<nX).map { x in Float(y * nX + x) } }
        return IBWFixtureBuilder.build(
            waveName: "SingleChan",
            nX: nX, nY: nY,
            channels: [IBWFixtureBuilder.Channel(label: "HeightRetrace", semanticType: "Height", values: values)],
            xScale: xScale, yScale: yScale
        )
    }

    @Test("parses version, checksum, and Float32 data for a minimal valid file")
    func parsesMinimalValidFile() throws {
        let data = makeHeightOnlyFixture()
        let wave = try IBWReader.read(data)
        #expect(wave.waveName == "SingleChan")
        #expect(wave.nDim == [3, 2, 1, 0])
        #expect(wave.floatValues == [0, 1, 2, 3, 4, 5])
    }

    @Test("rejects big-endian (PowerPC) files")
    func rejectsBigEndian() {
        var data = makeHeightOnlyFixture()
        // First byte zero => PowerPC/big-endian per Igor's own version-byte convention.
        data[0] = 0
        #expect(throws: IBWReadError.bigEndianUnsupported) {
            try IBWReader.read(data)
        }
    }

    @Test("rejects unsupported versions")
    func rejectsUnsupportedVersion() {
        var data = makeHeightOnlyFixture()
        data[0] = 3   // version 3, still non-zero first byte (little-endian) but unsupported
        #expect(throws: IBWReadError.unsupportedVersion(3)) {
            try IBWReader.read(data)
        }
    }

    @Test("rejects a corrupted checksum")
    func rejectsCorruptedChecksum() {
        var data = makeHeightOnlyFixture()
        // Flip a header byte without recomputing the checksum.
        data[40] ^= 0xff
        #expect(throws: IBWReadError.checksumMismatch) {
            try IBWReader.read(data)
        }
    }

    @Test("rejects a non-Float32 numeric type")
    func rejectsNonFloat32Type() {
        let data = makeHeightOnlyFixture()
        var bytes = [UInt8](data)
        // Change the type field (offset 64+16=80) to NT_FP64 (4) and recompute checksum.
        bytes[80] = 4
        bytes[81] = 0
        recomputeChecksum(&bytes)
        #expect(throws: IBWReadError.unsupportedNumericType(4)) {
            try IBWReader.read(Data(bytes))
        }
    }

    @Test("rejects a truncated file")
    func rejectsTruncatedFile() {
        let data = makeHeightOnlyFixture()
        let truncated = data.prefix(400)
        #expect(throws: IBWReadError.truncatedFile) {
            try IBWReader.read(Data(truncated))
        }
    }

    @Test("reads a 3D multichannel shape with correct dimension order")
    func readsMultichannelShape() throws {
        let nX = 4, nY = 3
        func plane(_ base: Float) -> [[Float]] {
            (0..<nY).map { y in (0..<nX).map { x in base + Float(y * nX + x) } }
        }
        let data = IBWFixtureBuilder.build(
            nX: nX, nY: nY,
            channels: [
                IBWFixtureBuilder.Channel(label: "HeightRetrace", semanticType: "Height", values: plane(0)),
                IBWFixtureBuilder.Channel(label: "DeflectionRetrace", semanticType: "Deflection", values: plane(100)),
                IBWFixtureBuilder.Channel(label: "ZSensorRetrace", semanticType: "ZSensor", values: plane(200)),
            ],
            xScale: 1e-7, yScale: 1e-7
        )
        let wave = try IBWReader.read(data)
        #expect(wave.nDim == [nX, nY, 3, 0])
        #expect(wave.floatValues.count == nX * nY * 3)
        // Column-major (dim0 fastest): first channel's block starts at index 0.
        #expect(wave.floatValues[0] == 0)
        #expect(wave.floatValues[nX * nY] == 100)         // start of channel 1
        #expect(wave.floatValues[2 * nX * nY] == 200)      // start of channel 2
    }

    @Test("reads X/Y dimension calibration (sfA/sfB)")
    func readsCalibration() throws {
        let data = makeHeightOnlyFixture(nX: 5, nY: 5, xScale: 2e-7, yScale: 3e-7)
        let wave = try IBWReader.read(data)
        #expect(wave.sfA[0] == 2e-7)
        #expect(wave.sfA[1] == 3e-7)
        #expect(wave.sfB[0] == 0)
        #expect(wave.sfB[1] == 0)
    }

    @Test("reads dimension units and data unit")
    func readsUnits() throws {
        let data = makeHeightOnlyFixture()
        let wave = try IBWReader.read(data)
        #expect(wave.dataUnit == "m")
        #expect(wave.dimUnits[0] == "m")
        #expect(wave.dimUnits[1] == "m")
    }

    @Test("reads channel dimension labels")
    func readsChannelLabels() throws {
        let nX = 2, nY = 2
        let values = (0..<nY).map { _ in [Float](repeating: 0, count: nX) }
        let data = IBWFixtureBuilder.build(
            nX: nX, nY: nY,
            channels: [
                IBWFixtureBuilder.Channel(label: "HeightRetrace", semanticType: "Height", values: values),
                IBWFixtureBuilder.Channel(label: "DeflectionRetrace", semanticType: "Deflection", values: values),
                IBWFixtureBuilder.Channel(label: "ZSensorRetrace", semanticType: "ZSensor", values: values),
            ],
            xScale: 1e-7, yScale: 1e-7
        )
        let wave = try IBWReader.read(data)
        #expect(wave.dimLabels[2] == ["", "HeightRetrace", "DeflectionRetrace", "ZSensorRetrace"])
    }

    @Test("reads semantic metadata (ChannelNDataType) from the note")
    func readsSemanticMetadataFromNote() throws {
        let data = makeHeightOnlyFixture()
        let wave = try IBWReader.read(data)
        #expect(wave.note.contains("Channel1DataType: Height"))
    }

    @Test("rejects a channel-dimension label count mismatch")
    func rejectsChannelLabelCountMismatch() throws {
        let nX = 2, nY = 2
        let values = (0..<nY).map { _ in [Float](repeating: 0, count: nX) }
        var bytes = [UInt8](IBWFixtureBuilder.build(
            nX: nX, nY: nY,
            channels: [
                IBWFixtureBuilder.Channel(label: "HeightRetrace", semanticType: "Height", values: values),
                IBWFixtureBuilder.Channel(label: "DeflectionRetrace", semanticType: "Deflection", values: values),
            ],
            xScale: 1e-7, yScale: 1e-7
        ))
        // dimLabelsSize[2] currently declares 3 labels (1 whole-dim + 2 channels) = 96 bytes.
        // Corrupt it to declare only 2 labels (64 bytes) while leaving the actual blob alone,
        // simulating a label count that doesn't match the channel count, then fix the checksum.
        setI32LEForTest(&bytes, 36 + 2 * 4, 64)
        recomputeChecksum(&bytes)
        #expect(throws: IBWReadError.channelLabelCountMismatch(expected: 2, found: 1)) {
            try IBWReader.read(Data(bytes))
        }
    }

    @Test("rejects malformed dimensions where declared point count doesn't match dims")
    func rejectsMalformedDimensions() throws {
        var bytes = [UInt8](makeHeightOnlyFixture(nX: 3, nY: 2))
        // Corrupt nY (offset 64+68+4=136) to 3 without changing npnts/data, then fix checksum.
        setI32LEForTest(&bytes, 64 + 68 + 4, 3)
        recomputeChecksum(&bytes)
        #expect(throws: IBWReadError.malformedDimensions) {
            try IBWReader.read(Data(bytes))
        }
    }

    // MARK: - Test-local byte helpers (mirrors IBWFixtureBuilder's private helpers for corruption tests)

    private func setI32LEForTest(_ buf: inout [UInt8], _ offset: Int, _ value: Int32) {
        let u = UInt32(bitPattern: value)
        buf[offset] = UInt8(u & 0xff)
        buf[offset + 1] = UInt8((u >> 8) & 0xff)
        buf[offset + 2] = UInt8((u >> 16) & 0xff)
        buf[offset + 3] = UInt8((u >> 24) & 0xff)
    }

    private func recomputeChecksum(_ buf: inout [UInt8]) {
        buf[2] = 0
        buf[3] = 0
        var sum: Int32 = 0
        for off in stride(from: 0, to: 384, by: 2) {
            let v = Int16(bitPattern: UInt16(buf[off]) | (UInt16(buf[off + 1]) << 8))
            sum += Int32(v)
        }
        let checksum = UInt16(bitPattern: Int16(truncatingIfNeeded: -sum))
        buf[2] = UInt8(checksum & 0xff)
        buf[3] = UInt8((checksum >> 8) & 0xff)
    }
}
