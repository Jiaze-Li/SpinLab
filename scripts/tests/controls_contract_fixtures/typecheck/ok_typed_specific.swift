import SwiftUI
struct Probe: WorkbenchLeafInput { var body: some View { HStack { Text("a") } } }
@MainActor func ok(b: Binding<Bool>) -> WorkbenchSpecificContent {
    WorkbenchSpecificContent {
        WorkbenchSpecificGroup("g", title: "G") {
            WorkbenchSpecificRow("r", label: "Row") {
                WorkbenchSpecificInput.toggle("t", title: "T", isOn: b)
                WorkbenchSpecificInput.control("c", Probe())
            }
        }
    }
}
