import SwiftUI
import UIKit

struct FileListRepresentable: UIViewControllerRepresentable {
    let url: URL
    var onNavigate: (URL) -> Void
    
    func makeUIViewController(context: Context) -> FileListViewController {
        let vc = FileListViewController(url: url)
        vc.onNavigate = onNavigate
        return vc
    }
    
    func updateUIViewController(_ uiViewController: FileListViewController, context: Context) {
        if uiViewController.currentURL != url {
            uiViewController.currentURL = url
            uiViewController.loadItems()
        }
    }
}
