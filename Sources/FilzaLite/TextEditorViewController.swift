import UIKit

class TextEditorViewController: UIViewController, UITextViewDelegate {
    private let url: URL
    private let textView = UITextView()
    private var originalText = ""
    
    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = url.lastPathComponent
        view.backgroundColor = .systemBackground
        
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        loadContent()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Save", comment: ""), style: .done, target: self, action: #selector(save))
    }
    
    private func loadContent() {
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
            textView.text = text
            originalText = text
        } else {
            textView.text = ""
            originalText = ""
        }
    }
    
    @objc private func save() {
        guard let data = textView.text.data(using: .utf8) else { return }
        try? data.write(to: url)
        originalText = textView.text
        let a = UIAlertController(title: nil, message: NSLocalizedString("Saved", comment: ""), preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { a.dismiss(animated: true) }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if textView.text != originalText {
            // 离开时自动保存
            try? textView.text.data(using: .utf8)?.write(to: url)
        }
    }
}
