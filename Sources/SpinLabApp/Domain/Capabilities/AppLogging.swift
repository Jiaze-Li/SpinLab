import Foundation

protocol AppLogging {
    func info(_ category: AppLogCategory, _ message: String, metadata: [String: String])
    func warning(_ category: AppLogCategory, _ message: String, metadata: [String: String])
    func error(_ category: AppLogCategory, _ message: String, metadata: [String: String])
}

extension AppLogger: AppLogging {}
