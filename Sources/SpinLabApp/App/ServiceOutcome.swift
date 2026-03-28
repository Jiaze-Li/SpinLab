import Foundation

enum WorkflowOutcome<Success> {
    case success(Success)
    case failure(AppError)
}

enum ReloadWorkflowOutcome<Success> {
    case unavailable
    case forward(URL)
    case success(Success)
    case failure(AppError)
}
