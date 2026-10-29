import SwiftUI
@MainActor func bad() -> WorkbenchSpecificGroup {
    WorkbenchSpecificGroup("g", title: "G") {
        VStack { Text("a") }
    }
}
