import SwiftUI
import UIKit

struct FileListRepresentable: UIViewControllerRepresentable {
    let url: URL
    let parentName: String
    var onNavigate: (URL) -> Void
    var onGoBack: () -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = FileListViewController.makeLinkedController(url: url)
        vc.parentName = parentName
        
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = false
        nav.view.backgroundColor = .systemBackground
        nav.isToolbarHidden = false
        return nav
    }
    
    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        nav.isToolbarHidden = false
    }
}
