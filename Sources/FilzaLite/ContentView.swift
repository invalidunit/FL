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
                // 更新当前标签的路径（保留已有标签）
                if let idx = FileListViewController.tabs.firstIndex(of: currentURL) {
                    FileListViewController.tabs[idx] = newURL
                } else if !FileListViewController.tabs.isEmpty {
                    FileListViewController.tabs[FileListViewController.tabs.count - 1] = newURL
                }
                currentURL = newURL
            },
            onGoBack: {
                let parent = currentURL.deletingLastPathComponent()
                // 只要父目录是允许的（Documents 下、App Group 下、Trash 下），就允许返回
                if FileService.shared.isAllowed(parent) {
                    currentURL = parent
                    if parent.standardizedFileURL == documentsURL.standardizedFileURL {
                        parentName = "/"
                    } else if parent.standardizedFileURL == FileService.shared.trashURL.standardizedFileURL {
                        parentName = "Trash"
                    } else if parent.standardizedFileURL == FileService.shared.groupURL?.standardizedFileURL {
                        parentName = "[App Group]"
                    } else {
                        parentName = parent.deletingLastPathComponent().lastPathComponent
                    }
                }
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
