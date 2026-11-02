import UIKit
import SwiftUI

class FileListViewController: UITableViewController {
    var currentURL: URL
    var items: [FileItem] = []
    var onNavigate: ((URL) -> Void)?
    var onSelectionChanged: (([FileItem]) -> Void)?
    
    private var selectedItems: Set<FileItem> = []
    private var isEditingMode = false
    
    init(url: URL) {
        self.currentURL = url
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = currentURL.lastPathComponent
        tableView.register(FileCell.self, forCellReuseIdentifier: "FileCell")
        tableView.rowHeight = 56
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 0)
        
        // Filza 风格工具栏
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped)),
            UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEdit))
        ]
        
        loadItems()
    }
    
    func loadItems() {
        items = FileService.shared.contents(of: currentURL)
        tableView.reloadData()
    }
    
    @objc private func toggleEdit() {
        isEditingMode.toggle()
        tableView.setEditing(isEditingMode, animated: true)
        navigationItem.rightBarButtonItems?.last?.title = isEditingMode ? "完成" : "编辑"
        if !isEditingMode {
            selectedItems.removeAll()
            onSelectionChanged?([])
        }
    }
    
    @objc private func addTapped() {
        let alert = UIAlertController(title: "新建", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "新建文件夹", style: .default) { _ in
            self.promptNewFolder()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func promptNewFolder() {
        let alert = UIAlertController(title: "新建文件夹", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "文件夹名称" }
        alert.addAction(UIAlertAction(title: "创建", style: .default) { _ in
            if let name = alert.textFields?.first?.text, !name.isEmpty {
                try? FileService.shared.createFolder(named: name, in: self.currentURL)
                self.loadItems()
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - TableView
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        let item = items[indexPath.row]
        cell.configure(with: item)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        
        if isEditingMode {
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
            onSelectionChanged?(Array(selectedItems))
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        
        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            // 简单预览提示（可扩展为文本/Hex/图片查看器）
            let alert = UIAlertController(title: item.name, message: "大小: \(item.displaySize)\n权限: \(item.permissions)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = items[indexPath.row]
            try? FileService.shared.delete(item: item)
            items.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}

// MARK: - Custom Cell（Filza 风格紧凑列表）
class FileCell: UITableViewCell {
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let sizeLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sizeLabel.font = .systemFont(ofSize: 13)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.textAlignment = .right
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(sizeLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -8),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            sizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            sizeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sizeLabel.widthAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    func configure(with item: FileItem) {
        nameLabel.text = item.name
        detailLabel.text = "\(item.displayDate)  \(item.permissions)"
        sizeLabel.text = item.displaySize
        
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        iconView.image = UIImage(systemName: item.isDirectory ? "folder.fill" : "doc.fill", withConfiguration: config)
        iconView.tintColor = item.isDirectory ? .systemBlue : .systemGray
    }
}
