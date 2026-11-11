import SwiftUI
import UIKit

struct FileListRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let root = FileListViewController(url: FileService.shared.documentsURL, parentTitle: "/")
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = false
        nav.isToolbarHidden = false
        return nav
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
