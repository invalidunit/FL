import SwiftUI

struct ContentView: View {
    var body: some View {
        FileListRepresentable()
            .ignoresSafeArea(edges: .bottom)
    }
}
