import UIKit

class FileListViewController: UITableViewController, UISearchResultsUpdating {
    var currentURL: URL
    var parentName: String = ""
    var items: [FileItem] = []
    var filteredItems: [FileItem] = []
    var onNavigate: ((URL) -> Void)?
    var onGoBack: (() -> Void)?
    
    private var sortMode: SortMode = .name
    private var isEditingMode = false
    private var selected = Set<FileItem>()
    
    private var clipboard: [FileItem] = []
    private var clipboardMode: ClipboardMode = .none
    
    private let selectedCountLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)
    private var isSearching: Bool { searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true) }
    
    static var history: [URL] = []
    static var favorites: [URL] = []
    static var tabs: [URL] = []
    
    private var isRoot: Bool {
        let cur = currentURL.standardizedFileURL
        let docs = FileService.shared.documentsURL.standardizedFileURL
        let trash = FileService.shared.trashURL.standardizedFileURL
        let group = FileService.shared.groupURL?.standardizedFileURL
        let caches = FileService.shared.cachesURL.standardizedFileURL
        return cur == docs || cur == trash || cur == group || cur == caches
    }
    
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
        setupSearch()
        setupSortHeader()
        setupBottomBar(editing: false)
        setupSelectedCount()
        loadItems()
        
        // 下拉刷新
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        tableView.refreshControl = refresh
        
        recordHistory(currentURL)
        // 不再在这里自动 append，避免每次导航都新增标签
        if FileListViewController.tabs.isEmpty {
            FileListViewController.tabs.append(currentURL)
        }
    }
    
    @objc private func refreshPulled() {
        loadItems()
        tableView.refreshControl?.endRefreshing()
    }
    
    private func recordHistory(_ url: URL) {
        FileListViewController.history.removeAll { $0 == url }
        FileListViewController.history.insert(url, at: 0)
        if FileListViewController.history.count > 50 {
            FileListViewController.history.removeLast()
        }
    }
    
    private func setupNavigation() {
        if isRoot {
            navigationItem.leftBarButtonItem = nil
            if currentURL.standardizedFileURL == FileService.shared.documentsURL.standardizedFileURL {
                title = "/"
            } else if currentURL.standardizedFileURL == FileService.shared.trashURL.standardizedFileURL {
                title = "Trash"
            } else if currentURL.standardizedFileURL == FileService.shared.cachesURL.standardizedFileURL {
                title = "[App Caches]"
            } else {
                title = "[App Group]"
            }
        } else {
            let backTitle = parentName.isEmpty ? "/" : parentName
            let back = makeBackButton(title: backTitle)
            navigationItem.leftBarButtonItem = back
            title = currentURL.lastPathComponent
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Edit", comment: ""), style: .plain, target: self, action: #selector(toggleEdit))
        
        // 临时调试：进入 Trash 时显示真实路径
        if currentURL.standardizedFileURL == FileService.shared.trashURL.standardizedFileURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let msg = "Trash path:\n\(self.currentURL.path)\nAllowed: \(FileService.shared.isAllowed(self.currentURL))"
                let a = UIAlertController(title: "Debug", message: msg, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(a, animated: true)
            }
        }
    }
    
    private func makeBackButton(title: String) -> UIBarButtonItem {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        btn.setTitle(" " + title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17)
        btn.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        btn.sizeToFit()
        return UIBarButtonItem(customView: btn)
    }
    
    func updateNavigation() {
        setupNavigation()
    }
    
    private func setupSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text?.lowercased() ?? ""
        filteredItems = items.filter { $0.name.lowercased().contains(text) }
        tableView.reloadData()
    }
    
    private func setupSortHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 40))
        header.backgroundColor = .systemGroupedBackground
        
        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.frame = CGRect(x: 10, y: 8, width: 28, height: 24)
        search.addTarget(self, action: #selector(focusSearch), for: .touchUpInside)
        
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
    
    @objc private func focusSearch() {
        searchController.isActive = true
        searchController.searchBar.becomeFirstResponder()
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
    
    private func setupSelectedCount() {
        selectedCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        selectedCountLabel.textColor = .white
        selectedCountLabel.backgroundColor = .systemGray
        selectedCountLabel.textAlignment = .center
        selectedCountLabel.layer.cornerRadius = 10
        selectedCountLabel.clipsToBounds = true
        selectedCountLabel.isHidden = true
        selectedCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectedCountLabel)
        NSLayoutConstraint.activate([
            selectedCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectedCountLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            selectedCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            selectedCountLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    private func updateSelectedCount() {
        if isEditingMode && !selected.isEmpty {
            selectedCountLabel.text = " \(selected.count) "
            selectedCountLabel.isHidden = false
        } else {
            selectedCountLabel.isHidden = true
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
            let paste = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(pasteTapped))
            let history = UIBarButtonItem(image: UIImage(systemName: "clock"), style: .plain, target: self, action: #selector(historyTapped))
            let star = UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: self, action: #selector(favoritesTapped))
            let gear = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsTapped))
            let tabs = UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: self, action: #selector(tabsTapped))
            toolbarItems = [paste, flex, history, flex, star, flex, gear, flex, tabs]
        }
        navigationController?.isToolbarHidden = false
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
    
    private func updateFooter() {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 36))
        let label = UILabel()
        
        let (used, total) = deviceStorage()
        let countText = items.isEmpty ? "Empty" : "\(items.count) item(s)."
        label.text = "\(used)/\(total)GB   \(countText)"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: footer.leadingAnchor, constant: 12)
        ])
        tableView.tableFooterView = footer
    }
    
    private func deviceStorage() -> (Int, Int) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let used = total - free
            let totalGB = Int(total / 1_000_000_000)
            let usedGB = Int(used / 1_000_000_000)
            return (usedGB, totalGB)
        } catch {
            return (0, 0)
        }
    }
    
    private func applySort() {
        switch sortMode {
        case .name: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: items.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .size: items.sort { $0.size > $1.size }
        }
    }
    
    @objc private func goBack() {
        if isRoot { return }
        let parent = currentURL.deletingLastPathComponent()
        if FileService.shared.isAllowed(parent) {
            onGoBack?()
        }
    }
    
    @objc private func toggleEdit() {
        isEditingMode.toggle()
        UIView.animate(withDuration: 0.25) {
            self.tableView.setEditing(self.isEditingMode, animated: true)
        }
        if isEditingMode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(toggleEdit))
        } else {
            setupNavigation()
            selected.removeAll()
        }
        setupBottomBar(editing: isEditingMode)
        updateSelectedCount()
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
    @objc private func moreTapped() {
        if isEditingMode && !selected.isEmpty {
            shareSelected()
        } else {
            showCreateSheet()
        }
    }
    
    private func shareSelected() {
        let urls = selected.map { $0.url }
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let p = activity.popoverPresentationController {
            p.barButtonItem = toolbarItems?.last
        }
        present(activity, animated: true)
    }
    
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
    
    private func promptNewFolder() {
        let a = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "Untitled Folder" }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            if let name = a.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                do {
                    try FileService.shared.createFolder(named: name, in: self.currentURL)
                    self.loadItems()
                } catch {
                    self.logError("Create folder failed: \(error.localizedDescription)")
                }
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
                do {
                    try FileService.shared.createEmptyFile(named: name, in: self.currentURL)
                    self.loadItems()
                } catch {
                    self.logError("Create file failed: \(error.localizedDescription)")
                }
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
        if !clipboard.isEmpty {
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
            return
        }
        
        if let text = UIPasteboard.general.string,
           let url = URL(string: text),
           url.scheme == "http" || url.scheme == "https" {
            confirmDownload(url)
        } else {
            flashMessage("Nothing to paste")
        }
    }
    
    private func confirmDownload(_ url: URL) {
        let name = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let a = UIAlertController(title: "Download", message: "File: \(name)\nFrom: \(url.host ?? "")", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Download", style: .default) { _ in
            self.downloadFromURL(url, name: name)
        })
        present(a, animated: true)
    }
    
    private func downloadFromURL(_ url: URL, name: String) {
        let dest = currentURL.appendingPathComponent(name)
        
        let alert = UIAlertController(title: "Downloading", message: name, preferredStyle: .alert)
        present(alert, animated: true)
        
        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            DispatchQueue.main.async {
                alert.dismiss(animated: true)
                if let tempURL = tempURL, error == nil {
                    try? FileManager.default.moveItem(at: tempURL, to: dest)
                    self.loadItems()
                    self.flashMessage("Downloaded")
                } else {
                    self.flashMessage("Download failed")
                }
            }
        }.resume()
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
            do {
                try FileService.shared.moveToTrash(item: item)
            } catch {
                self.logError("Move to trash failed: \(error.localizedDescription)")
            }
        }
        selected.removeAll()
        animateReload(fromRight: false)
        updateSelectedCount()
    }
    
    @objc private func historyTapped() {
        let vc = PathListViewController(title: "History", paths: FileListViewController.history) { [weak self] url in
            self?.dismiss(animated: true) {
                self?.onNavigate?(url)
            }
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @objc private func favoritesTapped() {
        let vc = FavoritesViewController(currentURL: currentURL) { [weak self] url in
            self?.dismiss(animated: true) {
                self?.onNavigate?(url)
            }
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @objc private func settingsTapped() {
        let vc = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @objc private func tabsTapped() {
        let vc = TabsPreviewViewController(tabs: FileListViewController.tabs, current: currentURL) { [weak self] url in
            self?.dismiss(animated: true) {
                self?.onNavigate?(url)
            }
        } onClose: { url in
            if let idx = FileListViewController.tabs.firstIndex(of: url) {
                FileListViewController.tabs.remove(at: idx)
            }
        } onAdd: {
            let relative = UserDefaults.standard.string(forKey: "defaultNewTabRelativePath") ?? ""
            var target = FileService.shared.documentsURL
            if relative == "[App Group]" || relative.lowercased() == "appgroup" {
                if let g = FileService.shared.groupURL {
                    target = g
                }
            } else if !relative.isEmpty {
                let candidate = FileService.shared.documentsURL.appendingPathComponent(relative)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    target = candidate
                }
            }
            FileListViewController.tabs.append(target)
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = isSearching ? filteredItems[indexPath.row] : items[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("Trash", comment: "")) { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            do {
                try FileService.shared.moveToTrash(item: item)
                // 淡出动画
                if let cell = tableView.cellForRow(at: indexPath) {
                    UIView.animate(withDuration: 0.25, animations: {
                        cell.alpha = 0
                        cell.transform = CGAffineTransform(translationX: -30, y: 0)
                    }) { _ in
                        self.loadItems()
                    }
                } else {
                    self.loadItems()
                }
                completion(true)
            } catch {
                completion(false)
            }
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
    
    private func animateReload(fromRight: Bool) {
        UIView.transition(with: tableView, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.loadItems()
        })
    }
    
    private func logError(_ message: String) {
        let logURL = FileService.shared.documentsURL.appendingPathComponent("error.log")
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
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
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = isSearching ? filteredItems[indexPath.row] : items[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let info = UIAction(title: "Info", image: UIImage(systemName: "info.circle")) { _ in
                self.showInfo(item)
            }
            let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                self.selected = [item]
                self.renameTapped()
            }
            let trash = UIAction(title: "Move to Trash", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                try? FileService.shared.moveToTrash(item: item)
                self.loadItems()
            }
            return UIMenu(title: "", children: [info, rename, trash])
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isSearching ? filteredItems.count : items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        let item = isSearching ? filteredItems[indexPath.row] : items[indexPath.row]
        cell.configure(with: item)
        cell.onInfo = { [weak self] in self?.showInfo(item) }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = isSearching ? filteredItems[indexPath.row] : items[indexPath.row]
        if isEditingMode {
            selected.insert(item)
            updateSelectedCount()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if item.isDirectory {
            if FileService.shared.isAllowed(item.url) {
                recordHistory(item.url)
                onNavigate?(item.url)
            }
        } else {
            openFile(item)
        }
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditingMode {
            let item = isSearching ? filteredItems[indexPath.row] : items[indexPath.row]
            selected.remove(item)
            updateSelectedCount()
        }
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

// 收藏夹
class FavoritesViewController: UITableViewController {
    private var favorites: [URL]
    private let currentURL: URL
    var onSelect: ((URL) -> Void)?
    
    private var systemItems: [(title: String, url: URL?, displayPath: String, icon: String)] = []
    
    init(currentURL: URL, onSelect: @escaping (URL) -> Void) {
        self.favorites = FileListViewController.favorites
        self.currentURL = currentURL
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = NSLocalizedString("Favorites", comment: "")
        
        systemItems.append(("[root]", FileService.shared.documentsURL, "/", "folder"))
        
        let group = FileService.shared.groupURL ?? FileService.shared.documentsURL.appendingPathComponent("AppGroupPlaceholder")
        systemItems.append(("[App Group]", group, "group.com.nan.filzalite", "folder.badge.person.crop"))
        
        systemItems.append(("Trash", FileService.shared.trashURL, ".appdata/Library/Trash", "trash"))
        
        systemItems.append(("[App Caches]", FileService.shared.cachesURL, ".appdata/Library/Caches", "folder"))
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCurrent))
    }
    
    @objc private func close() { dismiss(animated: true) }
    
    @objc private func addCurrent() {
        let alert = UIAlertController(
            title: NSLocalizedString("Add Favorite", comment: ""),
            message: NSLocalizedString("Enter relative path from / (leave empty for current)", comment: ""),
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "e.g. MyFolder/Sub"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { _ in
            let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url: URL
            if input.isEmpty {
                url = self.currentURL
            } else {
                // 只允许相对 Documents 的路径
                url = FileService.shared.documentsURL.appendingPathComponent(input)
            }
            if FileListViewController.favorites.contains(url) {
                self.flash(NSLocalizedString("Already in Favorites", comment: ""))
                return
            }
            FileListViewController.favorites.append(url)
            self.favorites = FileListViewController.favorites
            self.tableView.reloadData()
            self.flash(NSLocalizedString("Added", comment: ""))
        })
        present(alert, animated: true)
    }
    
    private func flash(_ text: String) {
        let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { a.dismiss(animated: true) }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? NSLocalizedString("Favorites", comment: "") : NSLocalizedString("System", comment: "")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? favorites.count : systemItems.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 {
            let url = favorites[indexPath.row]
            cell.textLabel?.text = url.lastPathComponent
            cell.detailTextLabel?.text = displayPath(for: url)
            cell.imageView?.image = UIImage(systemName: "star")
        } else {
            let item = systemItems[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = item.displayPath
            cell.imageView?.image = UIImage(systemName: item.icon)
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            onSelect?(favorites[indexPath.row])
        } else {
            if let url = systemItems[indexPath.row].url {
                onSelect?(url)
            }
        }
    }
    
    /// 把路径显示成以 Documents 为 / 的形式
    private func displayPath(for url: URL) -> String {
        let docs = FileService.shared.documentsURL.standardizedFileURL
        let target = url.standardizedFileURL
        if target == docs { return "/" }
        let docsPath = docs.path
        let targetPath = target.path
        if targetPath.hasPrefix(docsPath + "/") {
            return "/" + String(targetPath.dropFirst(docsPath.count + 1))
        }
        // 父目录或其他（如 /../）
        let parent = docs.deletingLastPathComponent()
        if target == parent { return "/../" }
        if targetPath.hasPrefix(parent.path + "/") {
            let rel = String(targetPath.dropFirst(parent.path.count + 1))
            return "/../" + rel
        }
        return url.lastPathComponent
    }
}

// 路径列表（历史）
class PathListViewController: UITableViewController {
    private var paths: [URL]
    var onSelect: ((URL) -> Void)?
    
    init(title: String, paths: [URL], onSelect: @escaping (URL) -> Void) {
        self.paths = paths
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
    }
    
    @objc private func close() { dismiss(animated: true) }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { paths.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let url = paths[indexPath.row]
        cell.textLabel?.text = url.lastPathComponent
        cell.detailTextLabel?.text = url.path
        cell.imageView?.image = UIImage(systemName: "clock")
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(paths[indexPath.row])
    }
}

// 多标签透视预览
class TabsPreviewViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private var tabs: [URL]
    private let current: URL
    var onSelect: ((URL) -> Void)?
    var onClose: ((URL) -> Void)?
    var onAdd: (() -> Void)?
    
    private var collectionView: UICollectionView!
    
    init(tabs: [URL], current: URL, onSelect: @escaping (URL) -> Void, onClose: @escaping (URL) -> Void, onAdd: @escaping () -> Void) {
        self.tabs = tabs
        self.current = current
        self.onSelect = onSelect
        self.onClose = onClose
        self.onAdd = onAdd
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tabs"
        view.backgroundColor = .systemBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTab))
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabPreviewCell.self, forCellWithReuseIdentifier: "TabCell")
        view.addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func close() { dismiss(animated: true) }
    
    @objc private func addTab() {
        onAdd?()
        tabs = FileListViewController.tabs
        collectionView.reloadData()
        flash("Added")
    }
    
    private func flash(_ text: String) {
        let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { a.dismiss(animated: true) }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { tabs.count }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TabCell", for: indexPath) as! TabPreviewCell
        let url = tabs[indexPath.item]
        cell.configure(url: url, isCurrent: url == current)
        cell.onClose = { [weak self] in
            guard let self = self else { return }
            self.onClose?(url)
            if indexPath.item < self.tabs.count {
                self.tabs.remove(at: indexPath.item)
            }
            collectionView.reloadData()
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: 220, height: 280)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(tabs[indexPath.item])
    }
}

class TabPreviewCell: UICollectionViewCell {
    private let preview = UIView()
    private let titleLabel = UILabel()
    private let closeBtn = UIButton(type: .system)
    private let listPreview = UIStackView()
    var onClose: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true
        
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.backgroundColor = .systemBackground
        preview.layer.cornerRadius = 8
        contentView.addSubview(preview)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .systemGray
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        contentView.addSubview(closeBtn)
        
        listPreview.translatesAutoresizingMaskIntoConstraints = false
        listPreview.axis = .vertical
        listPreview.spacing = 4
        preview.addSubview(listPreview)
        
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            closeBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            closeBtn.widthAnchor.constraint(equalToConstant: 24),
            closeBtn.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -4),
            
            preview.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            preview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            listPreview.topAnchor.constraint(equalTo: preview.topAnchor, constant: 8),
            listPreview.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 8),
            listPreview.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(url: URL, isCurrent: Bool) {
        titleLabel.text = url.lastPathComponent
        contentView.layer.borderWidth = isCurrent ? 2 : 0
        contentView.layer.borderColor = isCurrent ? UIColor.systemBlue.cgColor : nil
        
        listPreview.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let items = FileService.shared.contents(of: url).prefix(6)
        if items.isEmpty {
            let empty = UILabel()
            empty.text = "Empty"
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .secondaryLabel
            listPreview.addArrangedSubview(empty)
        } else {
            for item in items {
                let row = UILabel()
                row.font = .systemFont(ofSize: 11)
                row.text = (item.isDirectory ? "📁 " : "📄 ") + item.name
                row.lineBreakMode = .byTruncatingTail
                listPreview.addArrangedSubview(row)
            }
        }
    }
    
    @objc private func closeTapped() { onClose?() }
}

// 设置页
class SettingsViewController: UITableViewController {
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Settings", comment: "")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .done, target: self, action: #selector(close))
    }
    
    @objc private func close() { dismiss(animated: true) }
    
    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        NSLocalizedString("General", comment: "")
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = NSLocalizedString("New Tab Directory", comment: "")
        let rel = UserDefaults.standard.string(forKey: "defaultNewTabRelativePath") ?? ""
        cell.detailTextLabel?.text = rel.isEmpty ? "/" : rel
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        editNewTabDirectory()
    }
    
    private func editNewTabDirectory() {
        let current = UserDefaults.standard.string(forKey: "defaultNewTabRelativePath") ?? ""
        let alert = UIAlertController(
            title: NSLocalizedString("New Tab Directory", comment: ""),
            message: NSLocalizedString("Relative path from / (empty = /). If not exist, falls back to /.", comment: ""),
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = current
            tf.placeholder = "e.g. Downloads  or  [App Group]"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { _ in
            let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            UserDefaults.standard.set(input, forKey: "defaultNewTabRelativePath")
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}

// 文件类型图标
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
        
        let (symbol, color) = iconFor(item)
        let cfg = UIImage.SymbolConfiguration(pointSize: 22)
        icon.image = UIImage(systemName: symbol, withConfiguration: cfg)
        icon.tintColor = color
        chevron.isHidden = !item.isDirectory
    }
    
    private func iconFor(_ item: FileItem) -> (String, UIColor) {
        if item.isDirectory { return ("folder.fill", .systemBlue) }
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "deb": return ("shippingbox.fill", .systemOrange)
        case "ipa": return ("app.fill", .systemBlue)
        case "mp3", "m4a", "wav": return ("music.note", .systemPurple)
        case "png", "jpg", "jpeg", "gif", "heic": return ("photo", .systemGreen)
        case "pdf": return ("doc.richtext", .systemRed)
        case "zip", "tar", "gz", "7z": return ("doc.zipper", .systemBrown)
        case "txt", "md", "log": return ("doc.text", .systemGray)
        case "json", "xml", "plist", "yml", "yaml": return ("doc.text.fill", .systemTeal)
        case "swift", "m", "h", "c", "cpp", "py", "js": return ("chevron.left.forwardslash.chevron.right", .systemIndigo)
        default: return ("doc.fill", .systemGray)
        }
    }
    
    @objc private func infoTap() { onInfo?() }
}
