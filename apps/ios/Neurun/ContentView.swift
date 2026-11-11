import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .font(.title)
            .accessibilityIdentifier("hello-world")
    }
}

#Preview {
    ContentView()
}
