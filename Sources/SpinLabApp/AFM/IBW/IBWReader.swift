import Foundation

/// Typed failures for `IBWReader`. Each case names one distinct way a `.ibw` file can fail to
/// be a supported Igor Binary Wave v5 file — no case silently reinterprets a file as another
/// format or version.
enum IBWReadError: Error, Equatable, CustomStringConvertible {
    case truncatedFile
    case bigEndianUnsupported
    case unsupportedVersion(Int)
    case checksumMismatch
    case unsupportedNumericType(Int16)
    case malformedDimensions
    case channelLabelCountMismatch(expected: Int, found: Int)

    var description: String {
        switch self {
        case .truncatedFile:
            return "IBW file is truncated or shorter than its declared header/data size."
        case .bigEndianUnsupported:
            return "IBW file is big-endian (PowerPC-written); only the little-endian (Intel) variant is supported."
        case let .unsupportedVersion(v):
            return "Unsupported IBW version \(v); only version 5 is supported."
        case .checksumMismatch:
            return "IBW header checksum does not sum to zero; file is not a valid Igor binary wave."
        case let .unsupportedNumericType(t):
            return "Unsupported IBW numeric type 0x\(String(t, radix: 16)); only Float32 (NT_FP32) is supported."
        case .malformedDimensions:
            return "IBW wave dimensions are inconsistent with its declared point count or data size."
        case let .channelLabelCountMismatch(expected, found):
            return "IBW channel dimension has \(found) labels; expected \(expected) (one per channel)."
        }
    }
}

/// Raw decode of an Igor Binary Wave v5 file — byte-level only. Knows nothing about AFM,
/// Height/Deflection/ZSensor semantics, or physical unit conversion; that is
/// `AFMInputAdapter`'s job. See `docs/architecture/workbench/datasets/AFMDatasetContract.md`.
struct IBWWave: Equatable {
    /// Wave name (`WaveHeader5.bname`).
    let waveName: String
    /// Number of elements per dimension; always 4 entries, trailing zero(es) mean "unused".
    let nDim: [Int]
    /// Per-dimension scale: physical value for index `e` of dimension `d` is `sfA[d]*e + sfB[d]`.
    let sfA: [Double]
    let sfB: [Double]
    /// The wave's single data unit (shared across every channel — IBW has no per-channel unit).
    let dataUnit: String
    /// Per-dimension unit strings (4 entries).
    let dimUnits: [String]
    /// Per-dimension label lists. Index 0 of the list is the whole-dimension label; indices
    /// 1...N are per-element labels. Empty array = no labels stored for that dimension.
    let dimLabels: [[String]]
    /// Raw wave note text, undecoded beyond byte→string.
    let note: String
    /// Raw Float32 data, `nDim[0] × nDim[1] × max(nDim[2], 1)` elements, stored column-major
    /// (dimension 0 fastest) exactly as read from disk.
    let floatValues: [Float]
}

enum IBWReader {
    private static let binHeaderSize = 64
    private static let waveHeaderSize = 320   // WaveHeader5, up to but excluding wData
    private static let headerSize = binHeaderSize + waveHeaderSize   // 384; checksum span
    private static let ntFP32: Int16 = 2

    static func read(_ data: Data) throws -> IBWWave {
        // Random-access byte reads are far simpler and safer to reason about than unsafe
        // pointer arithmetic here; header parsing is a few hundred bytes and the float payload
        // (up to a few hundred thousand elements for a typical AFM scan) is small enough that
        // this costs nothing that matters.
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw IBWReadError.truncatedFile }

        // "If the first byte in the file is zero, the file is PowerPC/big-endian. If non-zero,
        // it is Intel/little-endian." (Igor TN003.) V1 only supports the little-endian variant.
        guard bytes[0] != 0 else { throw IBWReadError.bigEndianUnsupported }

        let version = Int(bytes.i16LE(at: 0))
        guard version == 5 else { throw IBWReadError.unsupportedVersion(version) }
        guard bytes.count >= headerSize else { throw IBWReadError.truncatedFile }

        // Checksum: sum of the first 384 bytes as signed 16-bit little-endian values must be 0.
        var checksum: Int32 = 0
        for offset in stride(from: 0, to: headerSize, by: 2) {
            checksum += Int32(bytes.i16LE(at: offset))
        }
        guard (checksum & 0xffff) == 0 else { throw IBWReadError.checksumMismatch }

        // BinHeader5 fields.
        let wfmSize = Int(bytes.i32LE(at: 4))
        let formulaSize = Int(bytes.i32LE(at: 8))
        let noteSize = Int(bytes.i32LE(at: 12))
        let dataEUnitsSize = Int(bytes.i32LE(at: 16))
        let dimEUnitsSize = (0..<4).map { Int(bytes.i32LE(at: 20 + $0 * 4)) }
        let dimLabelsSize = (0..<4).map { Int(bytes.i32LE(at: 36 + $0 * 4)) }

        // WaveHeader5 fields (offsets relative to file start; WaveHeader5 begins at binHeaderSize).
        let wh = binHeaderSize
        let npnts = Int(bytes.i32LE(at: wh + 12))
        let numericType = bytes.i16LE(at: wh + 16)
        let waveName = bytes.cString(at: wh + 28, maxLength: 32)
        let nDim = (0..<4).map { Int(bytes.i32LE(at: wh + 68 + $0 * 4)) }
        let sfA = (0..<4).map { bytes.f64LE(at: wh + 84 + $0 * 8) }
        let sfB = (0..<4).map { bytes.f64LE(at: wh + 116 + $0 * 8) }
        let dataUnitShort = bytes.cString(at: wh + 148, maxLength: 4)
        let dimUnitsShort = (0..<4).map { bytes.cString(at: wh + 152 + $0 * 4, maxLength: 4) }

        guard numericType == ntFP32 else { throw IBWReadError.unsupportedNumericType(numericType) }

        guard nDim[0] > 0, nDim[1] > 0, npnts > 0 else { throw IBWReadError.malformedDimensions }
        let channelCount = nDim[2] > 0 ? nDim[2] : 1
        guard nDim[0] * nDim[1] * channelCount == npnts else { throw IBWReadError.malformedDimensions }

        let dataStart = headerSize
        let dataByteCount = npnts * 4   // Float32
        guard wfmSize - waveHeaderSize == dataByteCount else { throw IBWReadError.malformedDimensions }
        guard bytes.count >= dataStart + dataByteCount else { throw IBWReadError.truncatedFile }

        var floatValues = [Float](repeating: 0, count: npnts)
        for i in 0..<npnts {
            floatValues[i] = bytes.f32LE(at: dataStart + i * 4)
        }

        // Optional data section: formula, note, dataEUnits, dimEUnits[4], dimLabels[4], sIndices —
        // in that fixed order (Igor TN003 "Storage Of Optional Data").
        var cursor = dataStart + dataByteCount
        cursor += formulaSize   // dependency formula text — not used by AFM, skipped

        guard bytes.count >= cursor + noteSize else { throw IBWReadError.truncatedFile }
        let note = bytes.latin1String(at: cursor, length: noteSize)
        cursor += noteSize

        var dataUnit = dataUnitShort
        if dataEUnitsSize > 0 {
            guard bytes.count >= cursor + dataEUnitsSize else { throw IBWReadError.truncatedFile }
            dataUnit = bytes.latin1String(at: cursor, length: dataEUnitsSize)
        }
        cursor += dataEUnitsSize

        var dimUnits = dimUnitsShort
        for d in 0..<4 {
            let size = dimEUnitsSize[d]
            guard size > 0 else { continue }
            guard bytes.count >= cursor + size else { throw IBWReadError.truncatedFile }
            dimUnits[d] = bytes.latin1String(at: cursor, length: size)
            cursor += size
        }

        var dimLabels: [[String]] = [[], [], [], []]
        for d in 0..<4 {
            let size = dimLabelsSize[d]
            guard size > 0 else { continue }
            guard size % 32 == 0 else { throw IBWReadError.malformedDimensions }
            guard bytes.count >= cursor + size else { throw IBWReadError.truncatedFile }
            let count = size / 32
            dimLabels[d] = (0..<count).map { bytes.cString(at: cursor + $0 * 32, maxLength: 32) }
            cursor += size
        }

        // Channel dimension label-count check: labels[0] is the whole-dimension label, so there
        // must be exactly channelCount + 1 entries if any labels are present at all.
        if !dimLabels[2].isEmpty, dimLabels[2].count != channelCount + 1 {
            throw IBWReadError.channelLabelCountMismatch(expected: channelCount, found: dimLabels[2].count - 1)
        }

        return IBWWave(
            waveName: waveName,
            nDim: nDim,
            sfA: sfA,
            sfB: sfB,
            dataUnit: dataUnit,
            dimUnits: dimUnits,
            dimLabels: dimLabels,
            note: note,
            floatValues: floatValues
        )
    }
}

// MARK: - Little-endian byte reads

private extension Array where Element == UInt8 {
    func u16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func i16LE(at offset: Int) -> Int16 {
        Int16(bitPattern: u16LE(at: offset))
    }

    func u32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func i32LE(at offset: Int) -> Int32 {
        Int32(bitPattern: u32LE(at: offset))
    }

    func f32LE(at offset: Int) -> Float {
        Float(bitPattern: u32LE(at: offset))
    }

    func f64LE(at offset: Int) -> Double {
        var bits: UInt64 = 0
        for i in 0..<8 {
            bits |= UInt64(self[offset + i]) << (8 * i)
        }
        return Double(bitPattern: bits)
    }

    /// Reads a null-terminated C string from a fixed-size field, stopping at the first NUL or
    /// `maxLength`, whichever comes first.
    func cString(at offset: Int, maxLength: Int) -> String {
        var end = offset
        let limit = offset + maxLength
        while end < limit, self[end] != 0 {
            end += 1
        }
        return String(decoding: self[offset..<end], as: UTF8.self)
    }

    /// Reads a fixed-length blob (no NUL termination expected, e.g. wave notes) as Latin-1 so
    /// every byte value decodes without failure.
    func latin1String(at offset: Int, length: Int) -> String {
        String(self[offset..<(offset + length)].map { Character(UnicodeScalar($0)) })
    }
}
