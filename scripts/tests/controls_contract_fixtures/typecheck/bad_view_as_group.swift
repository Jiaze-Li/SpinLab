import SwiftUI
@MainActor func bad() -> WorkbenchSpecificContent {
    WorkbenchSpecificContent {
        HStack { Text("a") }
    }
}
