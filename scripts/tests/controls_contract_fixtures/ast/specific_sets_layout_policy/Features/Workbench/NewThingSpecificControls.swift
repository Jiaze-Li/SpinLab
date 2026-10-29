import SwiftUI
struct NewThingFitInput: WorkbenchLeafInput {
    var body: some View {
        GeometryReader { proxy in
            ViewThatFits { Text("a"); Text("b") }
        }
    }
}
