import SwiftUI

struct ContentView: View {
    @State private var currentURL: URL = FileService.shared.documentsURL
    @State private var parentName: String = "/"
    
    private var documentsURL: URL { FileService.shared.documentsURL }
    
    var body: some View {
        FileListRepresentable(
            url: currentURL,
            parentName: parentName,
            onNavigate: { newURL in
                // 如果当前是 Documents，显示为 /
                if currentURL.standardizedFileURL == documentsURL.standardizedFileURL {
                    parentName = "/"
                } else {
                    parentName = currentURL.lastPathComponent
                }
                currentURL = newURL
            },
            onGoBack: {
                let parent = currentURL.deletingLastPathComponent()
                if parent.pathComponents.count >= documentsURL.pathComponents.count {
                    currentURL = parent
                    // 回到 Documents 时显示 /
                    if parent.standardizedFileURL == documentsURL.standardizedFileURL {
                        parentName = "/"
                    } else {
                        parentName = parent.deletingLastPathComponent().lastPathComponent
                    }
                }
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
