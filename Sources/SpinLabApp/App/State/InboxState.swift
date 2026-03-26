import Foundation
import Observation

@Observable
final class InboxState {
    let routing: InboxRoutingState

    init(routing: InboxRoutingState) {
        self.routing = routing
    }
}
