import Foundation

final class InboxState {
    let routing: InboxRoutingState

    init(routing: InboxRoutingState) {
        self.routing = routing
    }
}
