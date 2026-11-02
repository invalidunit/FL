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
    
    private var clipboard: [FileItem] = []
    private var clipboardMode: ClipboardMode = .none
    
    enum SortMode { case name, date, size }
    enum ClipboardMode { case none, copy, move }
    
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
        let back = UIBarButtonItem(title: parentName.isEmpty ? NSLocalizedString("Back", comment: "") : parentName, style: .plain, target: self, action: #selector(goBack))
        navigationItem.leftBarButtonItem = back
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Edit", comment: ""), style: .plain, target: self, action: #selector(toggleEdit))
        title = currentURL.lastPathComponent
    }
    
    func updateNavigation() {
        navigationItem.leftBarButtonItem?.title = parentName.isEmpty ? NSLocalizedString("Back", comment: "") : parentName
        title = currentURL.lastPathComponent
    }
    
    private func setupSortHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 40))
        header.backgroundColor = .systemGroupedBackground
        
        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.frame = CGRect(x: 10, y: 8, width: 28, height: 24)
        
        let name = makeSortButton(NSLocalizedString("Name", comment: ""), tag: 0)
        name.frame = CGRect(x: 50, y: 6, width: 70, height: 28)
        
        let date = makeSortButton(NSLocalizedString("Date", comment: ""), tag: 1)
        date.frame = CGRect(x: 130, y: 6, width: 60, height: 28)
        
        let size = makeSortButton(NSLocalizedString("Size", comment: ""), tag: 2)
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
            let copy = makeToolbarItem(title: NSLocalizedString("Copy", comment: ""), image: "doc.on.doc", action: #selector(copyTapped))
            let move = makeToolbarItem(title: NSLocalizedString("Move", comment: ""), image: "folder", action: #selector(moveTapped))
            let rename = makeToolbarItem(title: NSLocalizedString("Rename", comment: ""), image: "pencil", action: #selector(renameTapped))
            let trash = makeToolbarItem(title: NSLocalizedString("Trash", comment: ""), image: "trash", action: #selector(trashTapped))
            let more = makeToolbarItem(title: NSLocalizedString("More", comment: ""), image: "square.and.arrow.up", action: #selector(moreTapped))
            toolbarItems = [copy, flex, move, flex, rename, flex, trash, flex, more]
        } else {
            let clip = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(pasteTapped))
            let clock = UIBarButtonItem(image: UIImage(systemName: "clock"), style: .plain, target: self, action: #selector(recentsTapped))
            let star = UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: self, action: #selector(favoritesTapped))
            let gear = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsTapped))
            let win = UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: self, action: #selector(windowsTapped))
            toolbarItems = [clip, flex, clock, flex, star, flex, gear, flex, win]
        }
        navigationController?.isToolbarHidden = false
        // 底部栏背景
        navigationController?.toolbar.barTintColor = .secondarySystemBackground
        navigationController?.toolbar.isTranslucent = false
    }
    
    private func makeToolbarItem(title: String, image: String, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: image), style: .plain, target: self, action: action)
        item.title = title
        return item
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
    
    @objc private func goBack() {
        let parent = currentURL.deletingLastPathComponent()
        if FileService.shared.isAllowed(parent) {
            onGoBack?()
        }
    }
    
    @objc private func toggleEdit() {
        isEditingMode.toggle()
        tableView.setEditing(isEditingMode, animated: true)
        if isEditingMode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(toggleEdit))
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: parentName.isEmpty ? NSLocalizedString("Back", comment: "") : parentName, style: .plain, target: self, action: #selector(goBack))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Edit", comment: ""), style: .plain, target: self, action: #selector(toggleEdit))
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
    
    @objc private func addTapped() { showCreateSheet() }
    @objc private func moreTapped() { showCreateSheet() }
    
    private func showCreateSheet() {
        let sheet = UIAlertController(title: NSLocalizedString("More", comment: ""), message: nil, preferredStyle: .actionSheet)
        
        let newText = UIAlertAction(title: NSLocalizedString("New Text", comment: ""), style: .default) { _ in self.promptNewFile() }
        newText.setValue(UIImage(systemName: "doc.badge.plus"), forKey: "image")
        
        let newFolder = UIAlertAction(title: NSLocalizedString("New Folder", comment: ""), style: .default) { _ in self.promptNewFolder() }
        newFolder.setValue(UIImage(systemName: "folder.badge.plus"), forKey: "image")
        
        let link = UIAlertAction(title: NSLocalizedString("Shortcut", comment: ""), style: .default) { _ in }
        link.setValue(UIImage(systemName: "link.badge.plus"), forKey: "image")
        
        sheet.addAction(newText)
        sheet.addAction(newFolder)
        sheet.addAction(link)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        
        if let p = sheet.popoverPresentationController {
            p.barButtonItem = navigationItem.leftBarButtonItem
        }
        present(sheet, animated: true)
    }
    
    // Filza 风格输入框：Cancel / 输入框 / Done
    private func promptNewFolder() {
        let a = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "Untitled Folder" }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            if let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                try? FileService.shared.createFolder(named: name, in: self.currentURL)
                self.loadItems()
            }
        })
        present(a, animated: true)
    }
    
    private func promptNewFile() {
        let a = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "Untitled.txt" }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            if let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                try? FileService.shared.createEmptyFile(named: name, in: self.currentURL)
                self.loadItems()
            }
        })
        present(a, animated: true)
    }
    
    @objc private func copyTapped() {
        clipboard = Array(selected)
        clipboardMode = .copy
        flashMessage("Copied \(clipboard.count) item(s)")
    }
    
    @objc private func moveTapped() {
        clipboard = Array(selected)
        clipboardMode = .move
        flashMessage("Cut \(clipboard.count) item(s)")
    }
    
    @objc private func pasteTapped() {
        guard !clipboard.isEmpty else { return }
        for item in clipboard {
            switch clipboardMode {
            case .copy: try? FileService.shared.copy(item: item, to: currentURL)
            case .move: try? FileService.shared.move(item: item, to: currentURL)
            case .none: break
            }
        }
        if clipboardMode == .move {
            clipboard.removeAll()
            clipboardMode = .none
        }
        animateReload(fromRight: true)
    }
    
    @objc private func renameTapped() {
        guard selected.count == 1, let item = selected.first else {
            flashMessage("Select only one item to rename")
            return
        }
        let a = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        a.addTextField { $0.text = item.name }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            if let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != item.name {
                try? FileService.shared.rename(item: item, to: name)
                self.selected.removeAll()
                self.animateReload(fromRight: false)
            }
        })
        present(a, animated: true)
    }
    
    @objc private func trashTapped() {
        for item in selected {
            try? FileService.shared.moveToTrash(item: item)
        }
        selected.removeAll()
        animateReload(fromRight: false)
    }
    
    // 底部栏功能（视频里的收藏夹 / 最近 / 设置）
    @objc private func favoritesTapped() {
        let vc = SimpleListViewController(title: NSLocalizedString("Favorites", comment: ""), items: [
            "[jbroot]", "[rootfs]", "/rootfs/var", "Documents", "Applications", "CrashReporter"
        ])
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @objc private func recentsTapped() {
        let vc = SimpleListViewController(title: NSLocalizedString("Recents", comment: ""), items: [
            "Filza1", "Filza.entitlements", "build.yml", "Packages", "control"
        ])
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @objc private func settingsTapped() {
        let vc = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @objc private func windowsTapped() {
        flashMessage("Multi-window")
    }
    
    private func animateReload(fromRight: Bool) {
        let direction: CGFloat = fromRight ? 1 : -1
        UIView.transition(with: tableView, duration: 0.22, options: .transitionCrossDissolve, animations: {
            self.loadItems()
        })
        for cell in tableView.visibleCells {
            cell.transform = CGAffineTransform(translationX: direction * 40, y: 0)
            cell.alpha = 0.6
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            for cell in self.tableView.visibleCells {
                cell.transform = .identity
                cell.alpha = 1
            }
        }
    }
    
    private func flashMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            alert.dismiss(animated: true)
        }
    }
    
    private func isTextFile(_ item: FileItem) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        let textExts: Set<String> = ["txt", "text", "md", "json", "xml", "html", "htm", "css", "js", "swift", "m", "h", "c", "cpp", "py", "sh", "log", "plist", "yaml", "yml", "ini", "conf", "cfg"]
        if textExts.contains(ext) { return true }
        
        if ext.isEmpty {
            guard let data = try? Data(contentsOf: item.url, options: .mappedIfSafe) else { return false }
            let sample = data.prefix(4096)
            if sample.isEmpty { return true }
            let printable = sample.filter { $0 >= 32 && $0 < 127 || $0 == 9 || $0 == 10 || $0 == 13 }.count
            return Double(printable) / Double(sample.count) > 0.85
        }
        return false
    }
    
    private func openFile(_ item: FileItem) {
        if isTextFile(item) {
            let editor = TextEditorViewController(url: item.url)
            navigationController?.pushViewController(editor, animated: true)
        } else {
            showInfo(item)
        }
    }
    
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
        if item.isDirectory {
            if FileService.shared.isAllowed(item.url) {
                onNavigate?(item.url)
            }
        } else {
            openFile(item)
        }
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditingMode { selected.remove(items[indexPath.row]) }
    }
    
    private func showInfo(_ item: FileItem) {
        let msg = """
        Name: \(item.name)
        Size: \(item.displaySize)
        Date: \(item.displayDate)
        Path: \(item.url.path)
        """
        let a = UIAlertController(title: "Info", message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

// 简单列表（收藏夹 / 最近）
class SimpleListViewController: UITableViewController {
    private let items: [String]
    init(title: String, items: [String]) {
        self.items = items
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(close))
    }
    
    @objc private func close() { dismiss(animated: true) }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = items[indexPath.row]
        cell.imageView?.image = UIImage(systemName: "star")
        return cell
    }
}

// 设置页（对照视频里的设置）
class SettingsViewController: UITableViewController {
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Settings", comment: "")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(close))
    }
    
    @objc private func close() { dismiss(animated: true) }
    
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [4, 4, 2][section]
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["General", "WebDAV", "About"][section]
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        switch (indexPath.section, indexPath.row) {
        case (0, 0): cell.textLabel?.text = "Scroll Speed"; cell.detailTextLabel?.text = "Fast"
        case (0, 1): cell.textLabel?.text = "Show Hidden"; cell.detailTextLabel?.text = "Show"
        case (0, 2): cell.textLabel?.text = "Trash"
        case (0, 3): cell.textLabel?.text = "Advanced"
        case (1, 0): cell.textLabel?.text = "Port"; cell.detailTextLabel?.text = "10000"
        case (1, 1): cell.textLabel?.text = "Bonjour"; cell.detailTextLabel?.text = "Yes"
        case (1, 2): cell.textLabel?.text = "Auth"
        case (1, 3): cell.textLabel?.text = "Enable WebDAV"; cell.accessoryType = .disclosureIndicator
        case (2, 0): cell.textLabel?.text = "Activation"; cell.detailTextLabel?.text = "Full"
        case (2, 1): cell.textLabel?.text = "About"
        default: break
        }
        cell.accessoryType = .disclosureIndicator
        return cell
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
