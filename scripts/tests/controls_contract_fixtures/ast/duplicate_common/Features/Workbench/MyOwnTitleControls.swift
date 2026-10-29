import SwiftUI
struct MyOwnTitleControls: View {
    var body: some View { HStack { Toggle("Show Title", isOn: b); Text("Plot title") } }
}
