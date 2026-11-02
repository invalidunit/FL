import UIKit

class FileListViewController: UITableViewController {
    var currentURL: URL
    var parentName: String = ""
    var items: [FileItem] = []
    var onNavigate: ((URL) -> Void)?
    var onGoBack: (() -> Void)?
    
    private var sortMode: SortMode = .name
    private var isEditingMode = false
    private var selected = Set<FileItem>()
    
    enum SortMode { case name, date, size }
    
    init(url: URL) {
        self.currentURL = url
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(FileCell.self, forCellReuseIdentifier: "FileCell")
        tableView.rowHeight = 54
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 0)
        tableView.allowsMultipleSelectionDuringEditing = true
        
        setupNavigation()
        setupSortHeader()
        setupBottomBar(editing: false)
        loadItems()
    }
    
    private func setupNavigation() {
        let back = UIBarButtonItem(title: parentName.isEmpty ? "返回" : parentName, style: .plain, target: self, action: #selector(goBack))
        navigationItem.leftBarButtonItem = back
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEdit))
        title = currentURL.lastPathComponent
    }
    
    func updateNavigation() {
        navigationItem.leftBarButtonItem?.title = parentName.isEmpty ? "返回" : parentName
        title = currentURL.lastPathComponent
    }
    
    private func setupSortHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 40))
        header.backgroundColor = .systemGroupedBackground
        
        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.frame = CGRect(x: 10, y: 8, width: 28, height: 24)
        
        let name = makeSortButton("名称", tag: 0)
        name.frame = CGRect(x: 50, y: 6, width: 70, height: 28)
        
        let date = makeSortButton("日期", tag: 1)
        date.frame = CGRect(x: 130, y: 6, width: 60, height: 28)
        
        let size = makeSortButton("大小", tag: 2)
        size.frame = CGRect(x: 200, y: 6, width: 60, height: 28)
        
        let toggle = UIButton(type: .system)
        toggle.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        toggle.frame = CGRect(x: header.bounds.width - 44, y: 6, width: 32, height: 28)
        
        header.addSubview(search)
        header.addSubview(name)
        header.addSubview(date)
        header.addSubview(size)
        header.addSubview(toggle)
        
        tableView.tableHeaderView = header
        updateSortButtons()
    }
    
    private func makeSortButton(_ title: String, tag: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14)
        b.tag = tag
        b.addTarget(self, action: #selector(sortTapped(_:)), for: .touchUpInside)
        return b
    }
    
    private func updateSortButtons() {
        guard let header = tableView.tableHeaderView else { return }
        for v in header.subviews {
            guard let b = v as? UIButton, b.tag >= 0 && b.tag <= 2 else { continue }
            let active = (b.tag == 0 && sortMode == .name) || (b.tag == 1 && sortMode == .date) || (b.tag == 2 && sortMode == .size)
            b.setTitleColor(active ? .systemBlue : .label, for: .normal)
            if active {
                b.setImage(UIImage(systemName: "chevron.up"), for: .normal)
                b.semanticContentAttribute = .forceLeftToRight
                b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 0)
            } else {
                b.setImage(nil, for: .normal)
            }
        }
    }
    
    private func setupBottomBar(editing: Bool) {
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        if editing {
            let copy = UIBarButtonItem(title: "复制", style: .plain, target: self, action: #selector(copyTapped))
            let move = UIBarButtonItem(title: "移动", style: .plain, target: self, action: #selector(moveTapped))
            let rename = UIBarButtonItem(title: "重命名", style: .plain, target: self, action: #selector(renameTapped))
            let trash = UIBarButtonItem(title: "回收站", style: .plain, target: self, action: #selector(trashTapped))
            let more = UIBarButtonItem(title: "更多", style: .plain, target: self, action: #selector(moreTapped))
            toolbarItems = [copy, flex, move, flex, rename, flex, trash, flex, more]
        } else {
            let clip = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: nil, action: nil)
            let clock = UIBarButtonItem(image: UIImage(systemName: "clock"), style: .plain, target: nil, action: nil)
            let star = UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: nil, action: nil)
            let gear = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: nil, action: nil)
            let win = UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: nil, action: nil)
            toolbarItems = [clip, flex, clock, flex, star, flex, gear, flex, win]
        }
        navigationController?.isToolbarHidden = false
    }
    
    func loadItems() {
        items = FileService.shared.contents(of: currentURL)
        applySort()
        tableView.reloadData()
        updateFooter()
    }
    
    private func applySort() {
        switch sortMode {
        case .name: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: items.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .size: items.sort { $0.size > $1.size }
        }
    }
    
    private func updateFooter() {
        let label = UILabel()
        label.text = "/dev/disk1s8   --   \(items.count) item(s)."
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 30)
        tableView.tableFooterView = label
    }
    
    @objc private func goBack() { onGoBack?() }
    
    @objc private func toggleEdit() {
        isEditingMode.toggle()
        tableView.setEditing(isEditingMode, animated: true)
        if isEditingMode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(toggleEdit))
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: parentName.isEmpty ? "返回" : parentName, style: .plain, target: self, action: #selector(goBack))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEdit))
            selected.removeAll()
        }
        setupBottomBar(editing: isEditingMode)
    }
    
    @objc private func sortTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0: sortMode = .name
        case 1: sortMode = .date
        case 2: sortMode = .size
        default: break
        }
        updateSortButtons()
        loadItems()
    }
    
    @objc private func addTapped() {
        let sheet = UIAlertController(title: "更多", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "新文本", style: .default) { _ in self.promptNewFile() })
        sheet.addAction(UIAlertAction(title: "新建文件夹", style: .default) { _ in self.promptNewFolder() })
        sheet.addAction(UIAlertAction(title: "快捷链接", style: .default) { _ in })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let p = sheet.popoverPresentationController {
            p.barButtonItem = navigationItem.leftBarButtonItem
        }
        present(sheet, animated: true)
    }
    
    private func promptNewFolder() {
        let a = UIAlertController(title: "新建文件夹", message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "未命名文件夹" }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            if let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                try? FileService.shared.createFolder(named: name, in: self.currentURL)
                self.loadItems()
            }
        })
        present(a, animated: true)
    }
    
    private func promptNewFile() {
        let a = UIAlertController(title: "新文本", message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "未命名文件.txt" }
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            if let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                try? FileService.shared.createEmptyFile(named: name, in: self.currentURL)
                self.loadItems()
            }
        })
        present(a, animated: true)
    }
    
    @objc private func copyTapped() {}
    @objc private func moveTapped() {}
    @objc private func renameTapped() {}
    @objc private func trashTapped() {
        for item in selected {
            try? FileService.shared.delete(item: item)
        }
        selected.removeAll()
        loadItems()
    }
    @objc private func moreTapped() {}
    
    // MARK: Table
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        let item = items[indexPath.row]
        cell.configure(with: item)
        cell.onInfo = { [weak self] in self?.showInfo(item) }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        if isEditingMode {
            selected.insert(item)
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if item.isDirectory { onNavigate?(item.url) }
        else { showInfo(item) }
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditingMode { selected.remove(items[indexPath.row]) }
    }
    
    private func showInfo(_ item: FileItem) {
        let msg = """
        名称: \(item.name)
        大小: \(item.displaySize)
        日期: \(item.displayDate)
        路径: \(item.url.path)
        """
        let a = UIAlertController(title: "属性", message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "确定", style: .default))
        present(a, animated: true)
    }
}

// 更接近 Filza 的单元格：图标 + 名称 + 日期 + 大小 + ⓘ + 箭头
class FileCell: UITableViewCell {
    private let icon = UIImageView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let sizeLabel = UILabel()
    private let infoBtn = UIButton(type: .system)
    private let chevron = UIImageView()
    
    var onInfo: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 16)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .secondaryLabel
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.textAlignment = .right
        infoBtn.translatesAutoresizingMaskIntoConstraints = false
        infoBtn.setImage(UIImage(systemName: "info.circle"), for: .normal)
        infoBtn.addTarget(self, action: #selector(infoTap), for: .touchUpInside)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        
        [icon, nameLabel, dateLabel, sizeLabel, infoBtn, chevron].forEach { contentView.addSubview($0) }
        
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeLabel.leadingAnchor, constant: -8),
            
            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            
            sizeLabel.trailingAnchor.constraint(equalTo: infoBtn.leadingAnchor, constant: -6),
            sizeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sizeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            
            infoBtn.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -2),
            infoBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            infoBtn.widthAnchor.constraint(equalToConstant: 26),
            infoBtn.heightAnchor.constraint(equalToConstant: 26),
            
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
    }
    
    func configure(with item: FileItem) {
        nameLabel.text = item.name
        dateLabel.text = item.displayDate
        sizeLabel.text = item.isDirectory ? "" : item.displaySize
        
        let cfg = UIImage.SymbolConfiguration(pointSize: 22)
        icon.image = UIImage(systemName: item.isDirectory ? "folder.fill" : "doc.fill", withConfiguration: cfg)
        icon.tintColor = item.isDirectory ? .systemBlue : .systemGray
        chevron.isHidden = !item.isDirectory
    }
    
    @objc private func infoTap() { onInfo?() }
}
