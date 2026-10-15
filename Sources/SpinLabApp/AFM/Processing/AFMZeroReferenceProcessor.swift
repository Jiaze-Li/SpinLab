import Foundation

/// Applied last in the AFM processing pipeline: subtracts a single scalar offset from every
/// finite cell of the already-leveled/flattened matrix.
enum AFMZeroReferenceProcessor {
    static func apply(to matrix: [[Double]], reference: AFMZeroReference) -> [[Double]] {
        guard reference != .none else { return matrix }

        let finiteValues = matrix.lazy.flatMap { $0 }.filter { $0.isFinite }
        guard !finiteValues.isEmpty else { return matrix }

        let offset: Double
        switch reference {
        case .none:
            return matrix
        case .mean:
            offset = finiteValues.reduce(0, +) / Double(finiteValues.count)
        case .minimum:
            offset = finiteValues.min()!
        }

        return matrix.map { row in row.map { $0.isFinite ? $0 - offset : $0 } }
    }
}
