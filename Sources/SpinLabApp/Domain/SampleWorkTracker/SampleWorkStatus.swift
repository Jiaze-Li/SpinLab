import Foundation

enum SampleWorkStatus: Hashable, Sendable, Codable {
    case noData
    case todo
    case partial
    case hasChart

    static func derive(fileCount: Int, chartLinkedFileCount: Int) -> SampleWorkStatus {
        let files = max(0, fileCount)
        let linked = max(0, min(chartLinkedFileCount, files))
        switch (files, linked) {
        case (0, _):
            return .noData
        case (_, 0):
            return .todo
        case let (f, l) where l == f:
            return .hasChart
        default:
            return .partial
        }
    }
}
