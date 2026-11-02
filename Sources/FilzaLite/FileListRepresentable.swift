import SwiftUI
import UIKit

struct FileListRepresentable: UIViewControllerRepresentable {
    let url: URL
    let parentName: String
    var onNavigate: (URL) -> Void
    var onGoBack: () -> Void
    
    func makeUIViewController(context: Context) -> FileListViewController {
        let vc = FileListViewController(url: url)
        vc.parentName = parentName
        vc.onNavigate = onNavigate
        vc.onGoBack = onGoBack
        return vc
    }
    
    func updateUIViewController(_ uiViewController: FileListViewController, context: Context) {
        uiViewController.parentName = parentName
        if uiViewController.currentURL != url {
            uiViewController.currentURL = url
            uiViewController.loadItems()
        }
        uiViewController.updateNavigation()
    }
}
