import UIKit

class FileListViewController: UITableViewController {
    var currentURL: URL
    var items: [FileItem] = []
    var onNavigate: ((URL) -> Void)?
    var onSelectionChanged: (([FileItem]) -> Void)?
    
    private var selectedItems: Set<FileItem> = []
    private var isEditingMode = false
    private var searchController: UISearchController?
    private var filteredItems: [FileItem] = []
    private var isSearching = false
    
    init(url: URL) {
        self.currentURL = url
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = currentURL.lastPathComponent
        tableView.register(FileCell.self, forCellReuseIdentifier: "FileCell")
        tableView.rowHeight = 52
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 48, bottom: 0, right: 0)
        
        setupSearch()
        setupToolbar()
        loadItems()
    }
    
    private func setupSearch() {
        searchController = UISearchController(searchResultsController: nil)
        searchController?.searchResultsUpdater = self
        searchController?.obscuresBackgroundDuringPresentation = false
        searchController?.searchBar.placeholder = "搜索"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupToolbar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped)),
            UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEdit))
        ]
        
        // Filza 风格底部工具栏
        let pasteboard = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(pasteboardTapped))
        let recent = UIBarButtonItem(image: UIImage(systemName: "clock"), style: .plain, target: self, action: #selector(recentTapped))
        let fav = UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: self, action: #selector(favTapped))
        let settings = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsTapped))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolbarItems = [pasteboard, flex, recent, flex, fav, flex, settings]
        navigationController?.isToolbarHidden = false
    }
    
    func loadItems() {
        items = FileService.shared.contents(of: currentURL)
        filteredItems = items
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
        alert.addAction(UIAlertAction(title: "新建空文本", style: .default) { _ in
            self.promptNewFile()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(alert, animated: true)
    }
    
    private func promptNewFolder() {
        let alert = UIAlertController(title: "新建文件夹", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "文件夹名称" }
        alert.addAction(UIAlertAction(title: "创建", style: .default) { _ in
            if let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                do {
                    try FileService.shared.createFolder(named: name, in: self.currentURL)
                    self.loadItems()
                } catch {
                    self.showError(error)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func promptNewFile() {
        let alert = UIAlertController(title: "新建空文本", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "文件名（如 note.txt）" }
        alert.addAction(UIAlertAction(title: "创建", style: .default) { _ in
            if let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                do {
                    try FileService.shared.createEmptyFile(named: name, in: self.currentURL)
                    self.loadItems()
                } catch {
                    self.showError(error)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func pasteboardTapped() { showInfo("剪贴板功能待实现") }
    @objc private func recentTapped() { showInfo("最近文件待实现") }
    @objc private func favTapped() { showInfo("收藏待实现") }
    @objc private func settingsTapped() { showInfo("设置待实现") }
    
    private func showInfo(_ msg: String) {
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - TableView
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isSearching ? filteredItems.count : items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        let item = (isSearching ? filteredItems : items)[indexPath.row]
        cell.configure(with: item)
        cell.onInfo = { [weak self] in
            self?.showProperties(for: item)
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = (isSearching ? filteredItems : items)[indexPath.row]
        
        if isEditingMode {
            if selectedItems.contains(item) { selectedItems.remove(item) }
            else { selectedItems.insert(item) }
            onSelectionChanged?(Array(selectedItems))
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        
        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            showProperties(for: item)
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = (isSearching ? filteredItems : items)[indexPath.row]
            do {
                try FileService.shared.delete(item: item)
                loadItems()
            } catch {
                showError(error)
            }
        }
    }
    
    private func showProperties(for item: FileItem) {
        let msg = """
        名称: \(item.name)
        大小: \(item.displaySize)
        修改时间: \(item.displayDate)
        权限: \(item.permissions)
        路径: \(item.url.path)
        """
        let alert = UIAlertController(title: "属性", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension FileListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text, !text.isEmpty else {
            isSearching = false
            filteredItems = items
            tableView.reloadData()
            return
        }
        isSearching = true
        filteredItems = items.filter { $0.name.localizedCaseInsensitiveContains(text) }
        tableView.reloadData()
    }
}

// MARK: - Custom Cell（Filza 风格）
class FileCell: UITableViewCell {
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let sizeLabel = UILabel()
    private let infoButton = UIButton(type: .system)
    
    var onInfo: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.textAlignment = .right
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        infoButton.setImage(UIImage(systemName: "info.circle"), for: .normal)
        infoButton.tintColor = .systemBlue
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        infoButton.addTarget(self, action: #selector(infoTapped), for: .touchUpInside)
        
        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(sizeLabel)
        contentView.addSubview(infoButton)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -8),
            
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            
            sizeLabel.trailingAnchor.constraint(equalTo: infoButton.leadingAnchor, constant: -8),
            sizeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sizeLabel.widthAnchor.constraint(equalToConstant: 64),
            
            infoButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            infoButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            infoButton.widthAnchor.constraint(equalToConstant: 28),
            infoButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    func configure(with item: FileItem) {
        nameLabel.text = item.name
        detailLabel.text = "\(item.displayDate)"
        sizeLabel.text = item.displaySize
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        iconView.image = UIImage(systemName: item.isDirectory ? "folder.fill" : "doc.fill", withConfiguration: config)
        iconView.tintColor = item.isDirectory ? .systemBlue : .systemGray
    }
    
    @objc private func infoTapped() {
        onInfo?()
    }
}
