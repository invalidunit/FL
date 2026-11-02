import SwiftUI

struct ContentView: View {
    @State private var path: [URL] = []
    @State private var currentURL: URL = FileService.shared.documentsURL
    @State private var showPathBar = true
    
    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // Filza 风格路径栏
                if showPathBar {
                    PathBar(url: currentURL) { tappedURL in
                        navigateTo(tappedURL)
                    }
                    .background(Color(.systemGroupedBackground))
                    Divider()
                }
                
                // 核心列表（UIKit）
                FileListRepresentable(url: currentURL) { newURL in
                    path.append(newURL)
                    currentURL = newURL
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(currentURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: goUp) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentURL == FileService.shared.documentsURL)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showPathBar.toggle() }) {
                        Image(systemName: showPathBar ? "eye.slash" : "eye")
                    }
                }
            }
            .navigationDestination(for: URL.self) { url in
                // 子目录会通过 Representable 内部处理，这里保持路径同步
                EmptyView()
            }
        }
        .onAppear {
            path = []
            currentURL = FileService.shared.documentsURL
        }
    }
    
    private func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        if parent.pathComponents.count >= FileService.shared.documentsURL.pathComponents.count {
            currentURL = parent
            if !path.isEmpty { path.removeLast() }
        }
    }
    
    private func navigateTo(_ url: URL) {
        currentURL = url
        // 简化路径重建（生产环境可维护完整栈）
        path = []
    }
}

struct PathBar: View {
    let url: URL
    var onTap: (URL) -> Void
    
    private var components: [(name: String, url: URL)] {
        var result: [(String, URL)] = []
        var current = url
        let root = FileService.shared.documentsURL
        
        while current.path.hasPrefix(root.path) && current != root {
            result.insert((current.lastPathComponent, current), at: 0)
            current = current.deletingLastPathComponent()
        }
        result.insert(("Documents", root), at: 0)
        return result
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(components.enumerated()), id: \.offset) { index, comp in
                    Button(comp.name) {
                        onTap(comp.url)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(index == components.count - 1 ? .primary : .blue)
                    
                    if index < components.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 36)
    }
}
