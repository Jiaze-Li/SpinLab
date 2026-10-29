import SwiftUI

struct BadControl: View {
    @State private var on = true
    var body: some View {
        VStack {
            Toggle("Show Title", isOn: $on).toggleStyle(.checkbox)
            Text("Available").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
