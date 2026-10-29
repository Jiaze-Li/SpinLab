import SwiftUI
@MainActor func bad() -> WorkbenchSpecificInput {
    WorkbenchSpecificInput.control("c", Text("not a leaf input"))
}
