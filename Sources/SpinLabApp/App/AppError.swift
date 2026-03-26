import Foundation

enum AppError: LocalizedError, Equatable {
    case validation(String)
    case notFound(String)
    case io(String)
    case sync(String)
    case state(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message),
             let .notFound(message),
             let .io(message),
             let .sync(message),
             let .state(message),
             let .unknown(message):
            return message
        }
    }

    static func from(_ error: Error, fallback: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        let message = (error as NSError).localizedDescription
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknown(fallback)
        }
        return .unknown(message)
    }
}

struct AppAlertState: Identifiable, Equatable {
    let id: UUID = UUID()
    let title: String
    let message: String
}
