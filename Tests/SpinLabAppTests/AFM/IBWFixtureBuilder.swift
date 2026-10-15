import Foundation

/// Builds minimal, valid synthetic Igor Binary Wave v5 files in-memory for deterministic tests —
/// no real `.ibw` file is committed to the repo. Mirrors exactly the byte layout `IBWReader`
/// expects (BinHeader5[64] + WaveHeader5[320] + Float32 data + note + dim labels), validated
/// against Igor's own TN003 reference implementation and real Asylum Research `.ibw` files.
enum IBWFixtureBuilder {
    struct Channel {
        let label: String
        /// nil = omit the `Channel<N>DataType` note line entirely.
        let semanticType: String?
        /// `values[y][x]`.
        let values: [[Float]]
        var planefit: String? = nil
        var planefitOrder: Double? = nil
        var flattenOrder: Double? = nil
    }

    static func build(
        waveName: String = "TestWave",
        nX: Int,
        nY: Int,
        channels: [Channel],
        xScale: Double,
        yScale: Double,
        xUnit: String = "m",
        yUnit: String = "m",
        dataUnit: String = "m",
        extraNoteLines: [String] = [],
        omitChannelDimLabels: Bool = false
    ) -> Data {
        let nChannels = channels.count
        let npnts = nX * nY * nChannels

        var noteLines: [String] = []
        for (i, ch) in channels.enumerated() {
            if let semantic = ch.semanticType {
                noteLines.append("Channel\(i + 1)DataType: \(semantic)")
            }
            if let pf = ch.planefit { noteLines.append("Planefit \(i): \(pf)") }
            if let po = ch.planefitOrder { noteLines.append("PlanefitOrder \(i): \(po)") }
            if let fo = ch.flattenOrder { noteLines.append("FlattenOrder \(i): \(fo)") }
        }
        noteLines.append(contentsOf: extraNoteLines)
        let noteData = Array(noteLines.joined(separator: "\r").utf8)

        var dimLabelsBlob = [UInt8]()
        if !omitChannelDimLabels {
            appendFixed32Label("", to: &dimLabelsBlob)
            for ch in channels { appendFixed32Label(ch.label, to: &dimLabelsBlob) }
        }

        var floatBytes = [UInt8]()
        floatBytes.reserveCapacity(npnts * 4)
        for c in 0..<nChannels {
            for y in 0..<nY {
                for x in 0..<nX {
                    appendF32LE(channels[c].values[y][x], to: &floatBytes)
                }
            }
        }

        let dataByteCount = npnts * 4
        let wfmSize = Int32(320 + dataByteCount)

        var header = [UInt8](repeating: 0, count: 384)
        setI16LE(&header, 0, 5)                      // version
        setI16LE(&header, 2, 0)                       // checksum placeholder
        setI32LE(&header, 4, wfmSize)
        setI32LE(&header, 8, 0)                        // formulaSize
        setI32LE(&header, 12, Int32(noteData.count))   // noteSize
        setI32LE(&header, 16, 0)                       // dataEUnitsSize
        for d in 0..<4 { setI32LE(&header, 20 + d * 4, 0) }   // dimEUnitsSize
        var dimLabelsSize = [Int32](repeating: 0, count: 4)
        dimLabelsSize[2] = Int32(dimLabelsBlob.count)
        for d in 0..<4 { setI32LE(&header, 36 + d * 4, dimLabelsSize[d]) }
        setI32LE(&header, 52, 0)   // sIndicesSize
        setI16LE(&header, 56, 0)   // longWaveNameSize
        setI16LE(&header, 58, 0)   // optionsSize1
        setI32LE(&header, 60, 0)   // optionsSize2

        let wh = 64
        setI32LE(&header, wh + 12, Int32(npnts))
        setI16LE(&header, wh + 16, 2)   // NT_FP32
        setI16LE(&header, wh + 26, 1)   // whVersion
        setCString(&header, wh + 28, 32, waveName)
        setI32LE(&header, wh + 68 + 0 * 4, Int32(nX))
        setI32LE(&header, wh + 68 + 1 * 4, Int32(nY))
        setI32LE(&header, wh + 68 + 2 * 4, Int32(nChannels))
        setI32LE(&header, wh + 68 + 3 * 4, 0)
        setF64LE(&header, wh + 84 + 0 * 8, xScale)
        setF64LE(&header, wh + 84 + 1 * 8, yScale)
        setF64LE(&header, wh + 84 + 2 * 8, 1)
        setF64LE(&header, wh + 84 + 3 * 8, 1)
        setCString(&header, wh + 148, 4, dataUnit)
        setCString(&header, wh + 152 + 0 * 4, 4, xUnit)
        setCString(&header, wh + 152 + 1 * 4, 4, yUnit)

        // Checksum: sum of all int16 LE values across the 384-byte header must be zero.
        var sum: Int32 = 0
        for off in stride(from: 0, to: 384, by: 2) {
            sum += Int32(readI16LE(header, off))
        }
        setU16LE(&header, 2, UInt16(bitPattern: Int16(truncatingIfNeeded: -sum)))

        var result = header
        result.append(contentsOf: floatBytes)
        result.append(contentsOf: noteData)
        result.append(contentsOf: dimLabelsBlob)
        return Data(result)
    }

    // MARK: - Byte helpers

    private static func appendFixed32Label(_ s: String, to blob: inout [UInt8]) {
        var bytes = Array(s.utf8.prefix(31))
        bytes.append(0)
        while bytes.count < 32 { bytes.append(0) }
        blob.append(contentsOf: bytes)
    }

    private static func appendF32LE(_ value: Float, to bytes: inout [UInt8]) {
        let bits = value.bitPattern
        bytes.append(UInt8(bits & 0xff))
        bytes.append(UInt8((bits >> 8) & 0xff))
        bytes.append(UInt8((bits >> 16) & 0xff))
        bytes.append(UInt8((bits >> 24) & 0xff))
    }

    private static func setU16LE(_ buf: inout [UInt8], _ offset: Int, _ value: UInt16) {
        buf[offset] = UInt8(value & 0xff)
        buf[offset + 1] = UInt8((value >> 8) & 0xff)
    }

    private static func setI16LE(_ buf: inout [UInt8], _ offset: Int, _ value: Int16) {
        setU16LE(&buf, offset, UInt16(bitPattern: value))
    }

    private static func setI32LE(_ buf: inout [UInt8], _ offset: Int, _ value: Int32) {
        let u = UInt32(bitPattern: value)
        buf[offset] = UInt8(u & 0xff)
        buf[offset + 1] = UInt8((u >> 8) & 0xff)
        buf[offset + 2] = UInt8((u >> 16) & 0xff)
        buf[offset + 3] = UInt8((u >> 24) & 0xff)
    }

    private static func setF64LE(_ buf: inout [UInt8], _ offset: Int, _ value: Double) {
        let bits = value.bitPattern
        for i in 0..<8 {
            buf[offset + i] = UInt8((bits >> (8 * i)) & 0xff)
        }
    }

    private static func setCString(_ buf: inout [UInt8], _ offset: Int, _ maxLength: Int, _ s: String) {
        var bytes = Array(s.utf8.prefix(maxLength - 1))
        bytes.append(0)
        for (i, b) in bytes.enumerated() where i < maxLength {
            buf[offset + i] = b
        }
    }

    private static func readI16LE(_ buf: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(buf[offset]) | (UInt16(buf[offset + 1]) << 8))
    }
}
