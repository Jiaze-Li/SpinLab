import Foundation

/// Temporary instrumentation counters for diagnosing redundant SwiftUI body
/// rebuilds / series syncs / renders / snapshot flushes around workflow and
/// tab switches. Not thread-safe by design — all call sites are main-actor
/// SwiftUI body evaluations or main-thread store calls.
enum PerfCounters {
    static var controlsPanelBody = 0
    static var standardControlsBody = 0
    static var styleRowBody = 0
    static var typographyRowBody = 0
    static var seriesOrderPanelBody = 0
    static var seriesOrderSyncRows = 0
    static var renderCalls = 0
}
