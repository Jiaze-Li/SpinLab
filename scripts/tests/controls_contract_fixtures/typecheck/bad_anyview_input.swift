import SwiftUI
@MainActor func bad() -> WorkbenchSpecificInput {
    WorkbenchSpecificInput(id: "x") { AnyView(HStack { Text("arbitrary") }) }
}
