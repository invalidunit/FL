import SwiftUI
import UIKit

struct FileListRepresentable: UIViewControllerRepresentable {
    let url: URL
    let parentName: String
    var onNavigate: (URL) -> Void
    var onGoBack: () -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = FileListViewController(url: url)
        vc.parentName = parentName
        vc.onNavigate = onNavigate
        vc.onGoBack = onGoBack
        
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = false
        nav.isToolbarHidden = false
        return nav
    }
    
    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        guard let vc = nav.topViewController as? FileListViewController else { return }
        vc.parentName = parentName
        if vc.currentURL != url {
            vc.currentURL = url
            vc.loadItems()
        }
        vc.updateNavigation()
    }
}
