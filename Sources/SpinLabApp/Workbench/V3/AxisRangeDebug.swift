import Foundation

// MARK: - AxisRangeDebug

/// Gated by SPINLAB_DEBUG_AXIS_RANGE=1. Zero cost and zero output when disabled.
enum AxisRangeDebug {
    static let enabled = ProcessInfo.processInfo.environment["SPINLAB_DEBUG_AXIS_RANGE"] == "1"

    static func log(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        guard enabled else { return }
        let shortFile = file.split(separator: "/").last.map(String.init) ?? file
        print("[AxisRangeDebug \(shortFile):\(line)] \(message())")
    }
}
