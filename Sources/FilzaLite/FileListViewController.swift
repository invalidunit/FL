import UIKit
import UniformTypeIdentifiers

final class AppStore {
    static let shared = AppStore()
    var tabs: [URL] = []
    var index = 0
    var history: [URL] = []
    var favorites: [URL] = []
    var clipboard: [FileItem] = []
    var moving = false
    static let sortKey = "filza.sortButtons"
    static func sortTags() -> [Int] {
        let saved = UserDefaults.standard.array(forKey: sortKey) as? [Int] ?? [0, 1, 2]
        var seen = Set<Int>()
        let tags = saved.filter { (0...3).contains($0) && seen.insert($0).inserted }
        return tags.isEmpty ? [0] : tags
    }
}

final class FileListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIDocumentPickerDelegate {
    let currentURL: URL
    private var parentTitle: String
    private let table = UITableView(frame: .zero, style: .plain)
    private let sortBar = UIView()
    private let searchBar = UISearchBar()
    private let footer = UILabel()
    private var items: [FileItem] = []
    private var shown: [FileItem] = []
    private var query = ""
    private var searchVisible = false
    private var sort: Sort = .name
    private var selected = Set<URL>()
    private var float = BarFloat()
    private var didPlace = false
    private let barHeight: CGFloat = 36

    enum Sort { case name, date, size, type }

    init(url: URL, parentTitle: String) {
        self.currentURL = url
        self.parentTitle = parentTitle
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func displayTitle(for url: URL) -> String {
        let u = url.standardizedFileURL
        if u == FileService.shared.documentsURL.standardizedFileURL { return "/" }
        if u == FileService.shared.trashURL.standardizedFileURL { return "Trash" }
        if let g = FileService.shared.groupURL?.standardizedFileURL, u == g { return "[App Group]" }
        return u.lastPathComponent
    }

    private var isRoot: Bool {
        let u = currentURL.standardizedFileURL
        return u == FileService.shared.documentsURL.standardizedFileURL
            || u == FileService.shared.trashURL.standardizedFileURL
            || u == FileService.shared.groupURL?.standardizedFileURL
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 50
        table.separatorInset = .zero
        table.separatorColor = UIColor { $0.userInterfaceStyle == .dark ? .darkGray : UIColor(white: 0.85, alpha: 1) }
        table.contentInsetAdjustmentBehavior = .never
        table.register(RowCell.self, forCellReuseIdentifier: "row")
        table.allowsMultipleSelectionDuringEditing = true
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .gray
        footer.textAlignment = .right
        footer.numberOfLines = 2
        table.tableFooterView = footer
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reloadFromPull), for: .valueChanged)
        table.refreshControl = refresh
        view.addSubview(table)

        sortBar.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.96, alpha: 1) }
        sortBar.clipsToBounds = true
        view.addSubview(sortBar)
        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("Search", comment: "")
        searchBar.showsCancelButton = true
        searchBar.searchBarStyle = .minimal
        searchBar.isHidden = true
        view.addSubview(searchBar)

        if AppStore.shared.tabs.isEmpty { AppStore.shared.tabs = [currentURL] }
        remember(currentURL)
        styleBars()
        configureNav()
        rebuildSortBar()
        load()
        toolbar(editing: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let idx = AppStore.shared.index
        if AppStore.shared.tabs.indices.contains(idx) { AppStore.shared.tabs[idx] = currentURL }
        navigationController?.isToolbarHidden = false
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !isRoot
        styleBars()
        let tags = AppStore.sortTags()
        if !tags.contains(sortTag) {
            sort = sortFrom(tag: tags[0])
            load()
        }
        rebuildSortBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let top = view.safeAreaInsets.top
        table.frame = CGRect(x: 0, y: top, width: width, height: view.bounds.height - top)
        let searchH: CGFloat = searchVisible ? 56 : 0
        let inset = barHeight + searchH
        if table.contentInset.top != inset {
            table.contentInset.top = inset
            table.verticalScrollIndicatorInsets.top = inset
        }
        if !didPlace {
            didPlace = true
            float.reset(height: barHeight, offset: -barHeight - searchH)
            table.contentOffset.y = -inset
        }
        placeBars()
        if footer.bounds.width != width {
            footer.frame.size = CGSize(width: width - 16, height: 44)
            table.tableFooterView = footer
        }
    }

    private func placeBars() {
        let top = view.safeAreaInsets.top
        let width = view.bounds.width
        sortBar.frame = CGRect(x: 0, y: top + float.position, width: width, height: barHeight)
        searchBar.frame = CGRect(x: 0, y: sortBar.frame.maxY, width: width, height: searchVisible ? 56 : 0)
        view.bringSubviewToFront(sortBar)
        view.bringSubviewToFront(searchBar)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === table, didPlace else { return }
        float.scroll(offset: scrollView.contentOffset.y + (searchVisible ? 56 : 0), fixed: isEditing || searchVisible)
        placeBars()
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
    private func settle() {
        float.settle(offset: table.contentOffset.y + (searchVisible ? 56 : 0), fixed: isEditing || searchVisible)
        UIView.animate(withDuration: 0.2) { self.placeBars() }
    }

    private func styleBars() {
        guard let nav = navigationController else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.tintColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
        let bar = UIToolbarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(red: 246/255, green: 245/255, blue: 246/255, alpha: 1) }
        nav.toolbar.standardAppearance = bar
        nav.toolbar.scrollEdgeAppearance = bar
        nav.toolbar.tintColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
    }

    private func configureNav() {
        title = Self.displayTitle(for: currentURL)
        if isRoot {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: self, action: #selector(openFavorites))
        } else {
            let button = UIButton(type: .system)
            let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            button.setImage(UIImage(systemName: "chevron.left", withConfiguration: symbol), for: .normal)
            button.setTitle(" " + parentTitle, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.addTarget(self, action: #selector(goBack), for: .touchUpInside)
            button.sizeToFit()
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: button)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString(isEditing ? "Done" : "Edit", comment: ""), style: .plain, target: self, action: #selector(toggleEdit))
    }

    @objc private func goBack() { navigationController?.popViewController(animated: true) }

    private var sortTag: Int {
        switch sort { case .name: return 0; case .date: return 1; case .size: return 2; case .type: return 3 }
    }
    private func sortFrom(tag: Int) -> Sort {
        switch tag { case 1: return .date; case 2: return .size; case 3: return .type; default: return .name }
    }

    private func rebuildSortBar() {
        sortBar.subviews.forEach { $0.removeFromSuperview() }
        let left = UIButton(type: .system)
        left.tintColor = .label
        left.frame = CGRect(x: 6, y: 4, width: 32, height: 28)
        if isEditing {
            let all = !shown.isEmpty && selected.count == shown.count
            left.setImage(UIImage(systemName: all ? "checkmark.circle.fill" : "circle"), for: .normal)
            left.tintColor = all ? .systemBlue : .systemGray3
            left.addTarget(self, action: #selector(selectAll), for: .touchUpInside)
        } else {
            left.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
            left.addTarget(self, action: #selector(toggleSearch), for: .touchUpInside)
        }
        sortBar.addSubview(left)
        let titles = [NSLocalizedString("Name", comment: ""), NSLocalizedString("Date", comment: ""), NSLocalizedString("Size", comment: ""), NSLocalizedString("Type", comment: "")]
        let tags = AppStore.sortTags()
        let rightReserve: CGFloat = isEditing ? 8 : 36
        let usable = max(1, view.bounds.width - 44 - rightReserve)
        let col = usable / CGFloat(tags.count)
        for (i, tag) in tags.enumerated() {
            let button = UIButton(type: .system)
            button.tag = tag
            button.setTitle(titles[tag], for: .normal)
            button.titleLabel?.font = fittedFont(titles[tag], width: col - 18)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.55
            button.contentHorizontalAlignment = .center
            let on = tag == sortTag
            button.setTitleColor(on ? .systemBlue : .secondaryLabel, for: .normal)
            button.tintColor = on ? .systemBlue : .tertiaryLabel
            let cfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            button.setImage(UIImage(systemName: "chevron.up", withConfiguration: cfg), for: .normal)
            button.semanticContentAttribute = .forceRightToLeft
            button.frame = CGRect(x: 40 + col * CGFloat(i), y: 2, width: col, height: 32)
            button.addTarget(self, action: #selector(sortTapped(_:)), for: .touchUpInside)
            sortBar.addSubview(button)
        }
    }

    private func fittedFont(_ title: String, width: CGFloat) -> UIFont {
        var size: CGFloat = 14
        while size > 9 {
            let w = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
            if w <= width { return .systemFont(ofSize: size) }
            size -= 0.5
        }
        return .systemFont(ofSize: 9)
    }

    @objc private func sortTapped(_ sender: UIButton) {
        sort = sortFrom(tag: sender.tag)
        load()
        rebuildSortBar()
    }
    @objc private func selectAll() {
        if selected.count == shown.count { selected.removeAll() }
        else { selected = Set(shown.map(\.url)) }
        table.reloadData()
        rebuildSortBar()
        toolbar(editing: true)
    }
    @objc private func toggleSearch() {
        searchVisible.toggle()
        float.position = 0
        searchBar.isHidden = !searchVisible
        if searchVisible { searchBar.becomeFirstResponder() }
        else { query = ""; searchBar.text = ""; searchBar.resignFirstResponder(); applyFilter() }
        didPlace = false
        view.setNeedsLayout()
        table.reloadData()
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { query = searchText; applyFilter(); table.reloadData() }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchVisible = false
        query = ""
        searchBar.text = ""
        searchBar.isHidden = true
        searchBar.resignFirstResponder()
        didPlace = false
        applyFilter()
        view.setNeedsLayout()
        table.reloadData()
    }

    @objc private func reloadFromPull() { load(); table.refreshControl?.endRefreshing() }

    private func load() {
        items = FileService.shared.contents(of: currentURL)
        switch sort {
        case .name: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: items.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .size: items.sort { $0.size > $1.size }
        case .type: items.sort {
            let a = $0.url.pathExtension.lowercased(), b = $1.url.pathExtension.lowercased()
            if a == b { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        }
        applyFilter()
        table.reloadData()
        updateFooter()
    }
    private func applyFilter() {
        let q = query.lowercased()
        shown = q.isEmpty ? items : items.filter { $0.name.lowercased().contains(q) }
    }
    private func updateFooter() {
        let storage = disk()
        footer.text = "\(shown.count)  \(storage.0)/\(storage.1)GB"
    }
    private func disk() -> (Int, Int) {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return (Int((total - free) / 1_000_000_000), Int(total / 1_000_000_000))
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! RowCell
        let item = shown[indexPath.row]
        cell.fill(item, editing: isEditing, selected: selected.contains(item.url))
        cell.onInfo = { [weak self] in self?.showInfo(item) }
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = shown[indexPath.row]
        if isEditing {
            if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
            tableView.reloadRows(at: [indexPath], with: .none)
            toolbar(editing: true)
            rebuildSortBar()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if item.isDirectory {
            guard FileService.shared.isAllowed(item.url) else { return }
            remember(item.url)
            let child = FileListViewController(url: item.url, parentTitle: Self.displayTitle(for: currentURL))
            navigationController?.pushViewController(child, animated: true)
            let idx = AppStore.shared.index
            if AppStore.shared.tabs.indices.contains(idx) { AppStore.shared.tabs[idx] = item.url }
        } else {
            open(item)
        }
    }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = shown[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "")) { [weak self] _, _, done in
            self?.confirmDelete([item])
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = shown[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [
                UIAction(title: NSLocalizedString("Copy", comment: ""), image: UIImage(systemName: "doc.on.doc")) { _ in self.stash([item], move: false) },
                UIAction(title: NSLocalizedString("Move", comment: ""), image: UIImage(systemName: "folder")) { _ in self.stash([item], move: true) },
                UIAction(title: NSLocalizedString("Rename", comment: ""), image: UIImage(systemName: "pencil")) { _ in self.rename(item) },
                UIAction(title: NSLocalizedString("Info", comment: ""), image: UIImage(systemName: "info.circle")) { _ in self.showInfo(item) },
                UIAction(title: NSLocalizedString("Share", comment: ""), image: UIImage(systemName: "square.and.arrow.up")) { _ in self.share([item.url]) },
                UIAction(title: NSLocalizedString("Delete", comment: ""), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self.confirmDelete([item]) }
            ])
        }
    }

    private func open(_ item: FileItem) {
        let ext = item.url.pathExtension.lowercased()
        let text = ["txt", "md", "json", "xml", "plist", "strings", "log", "csv", "html", "css", "js", "swift", ""]
        if text.contains(ext) || ext.isEmpty {
            if let data = try? Data(contentsOf: item.url), data.count < 2_000_000, String(data: data, encoding: .utf8) != nil {
                navigationController?.pushViewController(TextEditorViewController(url: item.url), animated: true)
                return
            }
        }
        share([item.url])
    }

    @objc private func toggleEdit() {
        setEditing(!isEditing, animated: true)
        selected.removeAll()
        configureNav()
        if isEditing { navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addMenu)) }
        rebuildSortBar()
        toolbar(editing: isEditing)
        table.reloadData()
    }
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        table.setEditing(false, animated: false)
    }

    private func toolbar(editing: Bool) {
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        if editing {
            let on = !selected.isEmpty
            toolbarItems = [
                item("doc.on.doc", "Copy", #selector(copySelected), on), flex,
                item("folder", "Move", #selector(moveSelected), on), flex,
                item("pencil", "Rename", #selector(renameSelected), selected.count == 1), flex,
                item("trash", "Delete", #selector(deleteSelected), on), flex,
                item("square.and.arrow.up", "Share", #selector(shareSelected), on)
            ]
        } else {
            toolbarItems = [
                UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(pasteMenu)), flex,
                UIBarButtonItem(image: UIImage(systemName: "clock"), style: .plain, target: self, action: #selector(openHistory)), flex,
                UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: self, action: #selector(openFavorites)), flex,
                UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(openSettings)), flex,
                UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: self, action: #selector(openTabs))
            ]
        }
        navigationController?.isToolbarHidden = false
    }
    private func item(_ symbol: String, _ title: String, _ action: Selector, _ enabled: Bool) -> UIBarButtonItem {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
        button.setTitle(NSLocalizedString(title, comment: ""), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 10)
        button.tintColor = enabled ? .systemBlue : .systemGray3
        button.setTitleColor(button.tintColor, for: .normal)
        button.isEnabled = enabled
        button.alignVertical(spacing: 2)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 58, height: 44)
        return UIBarButtonItem(customView: button)
    }

    @objc private func addMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("New Folder", comment: ""), style: .default) { _ in self.promptCreate(folder: true) })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("New Text", comment: ""), style: .default) { _ in self.promptCreate(folder: false) })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Import", comment: ""), style: .default) { _ in self.importFiles() })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(sheet, animated: true)
    }
    private func promptCreate(folder: Bool) {
        let alert = UIAlertController(title: NSLocalizedString(folder ? "New Folder" : "New Text", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = folder ? "Folder" : "note.txt" }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            if folder { try? FileService.shared.createFolder(named: name, in: self.currentURL) }
            else { try? FileService.shared.createEmptyFile(named: name, in: self.currentURL) }
            self.load()
        })
        present(alert, animated: true)
    }
    private func importFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let dest = currentURL.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: url, to: dest) }
        }
        load()
    }

    private func chosen() -> [FileItem] { shown.filter { selected.contains($0.url) } }
    @objc private func copySelected() { stash(chosen(), move: false); finishEdit() }
    @objc private func moveSelected() { stash(chosen(), move: true); finishEdit() }
    private func stash(_ items: [FileItem], move: Bool) {
        AppStore.shared.clipboard = items
        AppStore.shared.moving = move
    }
    @objc private func renameSelected() { if let item = chosen().first { rename(item) } }
    private func rename(_ item: FileItem) {
        let alert = UIAlertController(title: NSLocalizedString("Rename", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = item.name }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, name != item.name else { return }
            try? FileService.shared.rename(item: item, to: name)
            self.load()
        })
        present(alert, animated: true)
    }
    @objc private func deleteSelected() { confirmDelete(chosen()) }
    private func confirmDelete(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let alert = UIAlertController(title: NSLocalizedString("Delete", comment: ""), message: items.map(\.name).joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { _ in
            let inTrash = self.currentURL.standardizedFileURL.path.hasPrefix(FileService.shared.trashURL.path)
            for item in items {
                if inTrash { try? FileService.shared.deletePermanently(item: item) }
                else { try? FileService.shared.moveToTrash(item: item) }
            }
            self.selected.subtract(items.map(\.url))
            self.load()
            if self.isEditing { self.toolbar(editing: true) }
        })
        present(alert, animated: true)
    }
    @objc private func shareSelected() { share(chosen().map(\.url)) }
    private func share(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        present(UIActivityViewController(activityItems: urls, applicationActivities: nil), animated: true)
    }
    private func finishEdit() {
        setEditing(false, animated: true)
        selected.removeAll()
        configureNav()
        rebuildSortBar()
        toolbar(editing: false)
        table.reloadData()
    }

    @objc private func pasteMenu() {
        let menu = UIAlertController(title: NSLocalizedString("Pasteboard", comment: ""), message: nil, preferredStyle: .actionSheet)
        if !AppStore.shared.clipboard.isEmpty {
            menu.addAction(UIAlertAction(title: NSLocalizedString("Paste", comment: ""), style: .default) { _ in self.pasteClipboard() })
            menu.addAction(UIAlertAction(title: NSLocalizedString("View", comment: ""), style: .default) { _ in self.showClipboard() })
            menu.addAction(UIAlertAction(title: NSLocalizedString("Clear", comment: ""), style: .default) { _ in AppStore.shared.clipboard = [] })
        } else if let text = UIPasteboard.general.string, let url = URL(string: text), url.scheme == "http" || url.scheme == "https" {
            menu.addAction(UIAlertAction(title: NSLocalizedString("Download", comment: ""), style: .default) { _ in self.confirmDownload(url) })
        }
        menu.addAction(UIAlertAction(title: NSLocalizedString("New Folder", comment: ""), style: .default) { _ in self.promptCreate(folder: true) })
        menu.addAction(UIAlertAction(title: NSLocalizedString("New Text", comment: ""), style: .default) { _ in self.promptCreate(folder: false) })
        menu.addAction(UIAlertAction(title: NSLocalizedString("Import", comment: ""), style: .default) { _ in self.importFiles() })
        menu.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(menu, animated: true)
    }
    private func pasteClipboard() {
        for item in AppStore.shared.clipboard {
            if AppStore.shared.moving { try? FileService.shared.move(item: item, to: currentURL) }
            else { try? FileService.shared.copy(item: item, to: currentURL) }
        }
        if AppStore.shared.moving { AppStore.shared.clipboard = [] }
        load()
    }
    private func showClipboard() {
        let vc = PlainListController(title: NSLocalizedString("Pasteboard", comment: ""), rows: AppStore.shared.clipboard.map(\.name)) { _ in }
        present(UINavigationController(rootViewController: vc), animated: true)
    }
    private func confirmDownload(_ url: URL) {
        let name = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let alert = UIAlertController(title: NSLocalizedString("Download", comment: ""), message: name, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Download", comment: ""), style: .default) { _ in
            let dest = self.currentURL.appendingPathComponent(name)
            URLSession.shared.downloadTask(with: url) { temp, _, _ in
                guard let temp else { return }
                try? FileManager.default.moveItem(at: temp, to: dest)
                DispatchQueue.main.async { self.load() }
            }.resume()
        })
        present(alert, animated: true)
    }

    private func remember(_ url: URL) {
        AppStore.shared.history.removeAll { $0 == url }
        AppStore.shared.history.insert(url, at: 0)
        if AppStore.shared.history.count > 40 { AppStore.shared.history.removeLast() }
    }
    @objc private func openHistory() {
        let rows = AppStore.shared.history.map { ($0, Self.displayTitle(for: $0)) }
        let vc = PathController(title: NSLocalizedString("History", comment: ""), rows: rows) { [weak self] url in
            self?.dismiss(animated: true) { self?.jump(url) }
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }
    @objc private func openFavorites() {
        let vc = FavoritesController(current: currentURL) { [weak self] url in
            self?.dismiss(animated: true) { self?.jump(url) }
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }
    @objc private func openSettings() {
        present(UINavigationController(rootViewController: SettingsController()), animated: true)
    }
    @objc private func openTabs() {
        let vc = TabsController()
        vc.onSelect = { [weak self] url in self?.dismiss(animated: true) { self?.jump(url) } }
        present(UINavigationController(rootViewController: vc), animated: true)
    }
    private func jump(_ url: URL) {
        guard FileService.shared.isAllowed(url) || url == FileService.shared.documentsURL else { return }
        remember(url)
        let root = FileListViewController(url: url, parentTitle: "/")
        navigationController?.setViewControllers([root], animated: true)
        let idx = AppStore.shared.index
        if AppStore.shared.tabs.indices.contains(idx) { AppStore.shared.tabs[idx] = url }
    }
    private func showInfo(_ item: FileItem) {
        present(UINavigationController(rootViewController: InfoController(item: item)), animated: true)
    }
}

private struct BarFloat {
    var height: CGFloat = 36
    var previous: CGFloat = -36
    var position: CGFloat = 0
    mutating func reset(height: CGFloat, offset: CGFloat) {
        self.height = height
        previous = offset
        position = 0
    }
    mutating func scroll(offset: CGFloat, fixed: Bool) {
        let old = previous
        previous = offset
        if fixed || offset <= -height { position = 0; return }
        let revealing = offset < old
        let partial = position < 0 && position > -height
        if (!revealing && offset > 0) || partial || (revealing && offset <= 0) || offset <= 0 {
            position = max(-height, min(0, position + old - offset))
        }
    }
    mutating func settle(offset: CGFloat, fixed: Bool) {
        if fixed || offset < 0 || position > -height / 2 { position = 0 } else { position = -height }
        previous = offset
    }
}

private final class RowCell: UITableViewCell {
    private let icon = UIImageView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let sizeLabel = UILabel()
    private let info = UIButton(type: .system)
    private let mark = UIImageView()
    private var markWidth: NSLayoutConstraint!
    var onInfo: (() -> Void)?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        nameLabel.font = .systemFont(ofSize: 17)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .lightGray
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .lightGray
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        info.setImage(UIImage(systemName: "info.circle"), for: .normal)
        info.addTarget(self, action: #selector(infoTap), for: .touchUpInside)
        [mark, icon, nameLabel, dateLabel, sizeLabel, info].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        markWidth = mark.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            mark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            markWidth,
            icon.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeLabel.leadingAnchor, constant: -6),
            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            sizeLabel.trailingAnchor.constraint(equalTo: info.leadingAnchor, constant: -4),
            sizeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            info.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            info.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            info.widthAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func fill(_ item: FileItem, editing: Bool, selected: Bool) {
        nameLabel.text = item.name
        dateLabel.text = item.displayDate
        sizeLabel.text = item.isDirectory ? "" : item.displaySize
        let symbol = item.isDirectory ? "folder.fill" : "doc.fill"
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = item.isDirectory ? .systemBlue : .systemGray
        info.isHidden = editing
        mark.isHidden = !editing
        markWidth.constant = editing ? 22 : 0
        mark.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        mark.tintColor = selected ? .systemBlue : .systemGray3
        contentView.backgroundColor = selected && editing ? UIColor(red: 233/255, green: 240/255, blue: 251/255, alpha: 1) : .systemBackground
    }
    @objc private func infoTap() { onInfo?() }
}

final class PlainListController: UITableViewController {
    private let rows: [String]
    private let pick: (Int) -> Void
    init(title: String, rows: [String], pick: @escaping (Int) -> Void) {
        self.rows = rows
        self.pick = pick
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = rows[indexPath.row]
        cell.selectionStyle = .none
        return cell
    }
}

final class PathController: UITableViewController {
    private let rows: [(URL, String)]
    private let pick: (URL) -> Void
    init(title: String, rows: [(URL, String)], pick: @escaping (URL) -> Void) {
        self.rows = rows
        self.pick = pick
        super.init(style: .plain)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 44
        tableView.separatorInset = .zero
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = rows[indexPath.row].1
        cell.imageView?.image = UIImage(systemName: "clock")
        cell.separatorInset = .zero
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { pick(rows[indexPath.row].0) }
}

final class FavoritesController: UITableViewController {
    private let current: URL
    private let pick: (URL) -> Void
    private var user: [URL] { AppStore.shared.favorites }
    init(current: URL, pick: @escaping (URL) -> Void) {
        self.current = current
        self.pick = pick
        super.init(style: .plain)
        title = NSLocalizedString("Favorites", comment: "")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 44
        tableView.separatorInset = .zero
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func add() {
        let alert = UIAlertController(title: NSLocalizedString("Add Favorite", comment: ""), message: NSLocalizedString("Enter relative path from / (leave empty for current)", comment: ""), preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Folder" }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { _ in
            let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = text.isEmpty ? self.current : FileService.shared.documentsURL.appendingPathComponent(text)
            if AppStore.shared.favorites.contains(url) { return }
            AppStore.shared.favorites.append(url)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? user.count : 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 1 ? NSLocalizedString("System", comment: "") : nil }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.separatorInset = .zero
        if indexPath.section == 0 {
            let url = user[indexPath.row]
            cell.textLabel?.text = FileListViewController.displayTitle(for: url)
            cell.detailTextLabel?.text = relative(url)
            cell.imageView?.image = UIImage(systemName: "star.fill")
            cell.imageView?.tintColor = .systemBlue
        } else {
            let titles = ["[root]", "[App Group]", "Trash"]
            let paths = ["/", "group.com.nan.filzalite", ".appdata/Library/Trash"]
            let icons = ["folder.fill", "person.crop.rectangle", "trash.fill"]
            cell.textLabel?.text = titles[indexPath.row]
            cell.detailTextLabel?.text = paths[indexPath.row]
            cell.imageView?.image = UIImage(systemName: icons[indexPath.row])
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 { pick(user[indexPath.row]); return }
        if indexPath.row == 0 { pick(FileService.shared.documentsURL) }
        else if indexPath.row == 1 { pick(FileService.shared.groupURL ?? FileService.shared.documentsURL) }
        else { pick(FileService.shared.trashURL) }
    }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { indexPath.section == 0 }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        AppStore.shared.favorites.remove(at: indexPath.row)
        tableView.reloadData()
    }
    private func relative(_ url: URL) -> String {
        let docs = FileService.shared.documentsURL.standardizedFileURL
        if url.standardizedFileURL == docs { return "/" }
        let path = url.standardizedFileURL.path
        if path.hasPrefix(docs.path + "/") { return "/" + path.dropFirst(docs.path.count + 1) }
        return FileListViewController.displayTitle(for: url)
    }
}

final class SettingsController: UITableViewController {
    init() { super.init(style: .insetGrouped); title = NSLocalizedString("Settings", comment: "") }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { NSLocalizedString("General", comment: "") }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.row == 0 {
            cell.textLabel?.text = NSLocalizedString("New Tab Directory", comment: "")
            let rel = UserDefaults.standard.string(forKey: "defaultNewTabRelativePath") ?? ""
            cell.detailTextLabel?.text = rel.isEmpty ? "/" : rel
            cell.accessoryType = .disclosureIndicator
        } else if indexPath.row == 1 {
            cell.textLabel?.text = NSLocalizedString("Sort Buttons", comment: "")
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.textLabel?.text = NSLocalizedString("Clear Cache", comment: "")
            cell.textLabel?.textColor = .systemRed
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 { editStart() }
        else if indexPath.row == 1 { navigationController?.pushViewController(SortButtonsController(), animated: true) }
        else {
            try? FileService.shared.clearCaches()
            let alert = UIAlertController(title: nil, message: NSLocalizedString("Cache cleared", comment: ""), preferredStyle: .alert)
            present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { alert.dismiss(animated: true) }
        }
    }
    private func editStart() {
        let alert = UIAlertController(title: NSLocalizedString("New Tab Directory", comment: ""), message: NSLocalizedString("Relative path from / (empty = /). If not exist, falls back to /.", comment: ""), preferredStyle: .alert)
        alert.addTextField { $0.text = UserDefaults.standard.string(forKey: "defaultNewTabRelativePath") }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { _ in
            UserDefaults.standard.set(alert.textFields?.first?.text ?? "", forKey: "defaultNewTabRelativePath")
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}

final class SortButtonsController: UITableViewController {
    private let names = ["Name", "Date", "Size", "Type"]
    private var enabled: Set<Int>
    init() {
        enabled = Set(AppStore.sortTags())
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Sort Buttons", comment: "")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { names.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = NSLocalizedString(names[indexPath.row], comment: "")
        cell.accessoryType = enabled.contains(indexPath.row) ? .checkmark : .none
        cell.tintColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if enabled.contains(indexPath.row) {
            guard enabled.count > 1 else { return }
            enabled.remove(indexPath.row)
        } else { enabled.insert(indexPath.row) }
        UserDefaults.standard.set(names.indices.filter { enabled.contains($0) }, forKey: AppStore.sortKey)
        tableView.reloadData()
    }
}

final class TabsController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: ((URL) -> Void)?
    private var collection: UICollectionView!
    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Tabs", comment: "")
        view.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .darkGray : UIColor(white: 2.0/3.0, alpha: 1) }
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(TabCard.self, forCellWithReuseIdentifier: "card")
        view.addSubview(collection)
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func add() {
        let rel = UserDefaults.standard.string(forKey: "defaultNewTabRelativePath") ?? ""
        var url = FileService.shared.documentsURL
        if rel == "[App Group]", let g = FileService.shared.groupURL { url = g }
        else if !rel.isEmpty {
            let candidate = FileService.shared.documentsURL.appendingPathComponent(rel)
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &dir), dir.boolValue { url = candidate }
        }
        AppStore.shared.tabs.append(url)
        AppStore.shared.index = AppStore.shared.tabs.count - 1
        collection.reloadData()
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { AppStore.shared.tabs.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "card", for: indexPath) as! TabCard
        let url = AppStore.shared.tabs[indexPath.item]
        cell.fill(url, current: indexPath.item == AppStore.shared.index)
        cell.onClose = { [weak self] in
            guard AppStore.shared.tabs.indices.contains(indexPath.item) else { return }
            AppStore.shared.tabs.remove(at: indexPath.item)
            if AppStore.shared.tabs.isEmpty { AppStore.shared.tabs = [FileService.shared.documentsURL] }
            AppStore.shared.index = min(AppStore.shared.index, AppStore.shared.tabs.count - 1)
            self?.collection.reloadData()
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width * 0.86
        return CGSize(width: width, height: min(360, width * 1.15))
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let side = collectionView.bounds.width * 0.07
        return UIEdgeInsets(top: 16, left: side, bottom: 24, right: side)
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        AppStore.shared.index = indexPath.item
        onSelect?(AppStore.shared.tabs[indexPath.item])
    }
}

final class TabCard: UICollectionViewCell {
    private let title = UILabel()
    private let close = UIButton(type: .system)
    private let stack = UIStackView()
    var onClose: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textAlignment = .center
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .systemRed
        close.addTarget(self, action: #selector(closed), for: .touchUpInside)
        stack.axis = .vertical
        [title, close, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            close.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            close.widthAnchor.constraint(equalToConstant: 32),
            title.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 44),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        contentView.addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError() }
    func fill(_ url: URL, current: Bool) {
        title.text = FileListViewController.displayTitle(for: url)
        contentView.layer.borderWidth = current ? 2 : 0
        contentView.layer.borderColor = UIColor.systemBlue.cgColor
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = FileService.shared.contents(of: url).prefix(6)
        if items.isEmpty {
            let empty = UILabel()
            empty.text = NSLocalizedString("Empty", comment: "")
            empty.textColor = .secondaryLabel
            stack.addArrangedSubview(empty)
        } else {
            for item in items {
                let label = UILabel()
                label.font = .systemFont(ofSize: 14)
                label.text = item.name
                stack.addArrangedSubview(label)
            }
        }
    }
    @objc private func closed() { onClose?() }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let x = gesture.translation(in: contentView).x
        if gesture.state == .changed {
            contentView.transform = CGAffineTransform(translationX: x, y: 0)
        } else if gesture.state == .ended {
            if abs(x) > 80 { onClose?() }
            UIView.animate(withDuration: 0.2) { self.contentView.transform = .identity }
        }
    }
}

final class InfoController: UITableViewController {
    private let rows: [(String, String)]
    init(item: FileItem) {
        var rows = [
            (NSLocalizedString("Name", comment: ""), item.name),
            (NSLocalizedString("Size", comment: ""), item.displaySize),
            (NSLocalizedString("Date", comment: ""), item.displayDate)
        ]
        if item.isDirectory {
            rows.insert((NSLocalizedString("Items", comment: ""), "\(FileService.shared.contents(of: item.url).count)"), at: 2)
        }
        self.rows = rows
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Info", comment: "")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = rows[indexPath.row].0
        cell.detailTextLabel?.text = rows[indexPath.row].1
        cell.selectionStyle = .none
        return cell
    }
}

extension UIButton {
    func alignVertical(spacing: CGFloat) {
        guard let imageSize = imageView?.image?.size, let text = titleLabel?.text, let font = titleLabel?.font else { return }
        let titleSize = (text as NSString).size(withAttributes: [.font: font])
        titleEdgeInsets = UIEdgeInsets(top: imageSize.height + spacing, left: -imageSize.width, bottom: 0, right: 0)
        imageEdgeInsets = UIEdgeInsets(top: -(titleSize.height + spacing), left: 0, bottom: 0, right: -titleSize.width)
        contentEdgeInsets = UIEdgeInsets(top: spacing, left: 0, bottom: spacing, right: 0)
    }
}
