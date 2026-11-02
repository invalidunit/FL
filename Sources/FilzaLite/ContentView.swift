import SwiftUI

struct ContentView: View {
    @State private var currentURL: URL = FileService.shared.documentsURL
    @State private var parentName: String = "返回"
    
    var body: some View {
        FileListRepresentable(
            url: currentURL,
            parentName: parentName,
            onNavigate: { newURL in
                parentName = currentURL.lastPathComponent
                currentURL = newURL
            },
            onGoBack: {
                let parent = currentURL.deletingLastPathComponent()
                if parent.pathComponents.count >= FileService.shared.documentsURL.pathComponents.count {
                    currentURL = parent
                    parentName = currentURL.deletingLastPathComponent().lastPathComponent
                }
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
