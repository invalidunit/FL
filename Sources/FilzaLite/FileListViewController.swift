import UIKit

class FileListViewController: UITableViewController {
    var currentURL: URL
    var parentName: String = ""
    var items: [FileItem] = []
    var onNavigate: ((URL) -> Void)?
    var onGoBack: (() -> Void)?
    
    private var sortMode: SortMode = .name
    private var isGrid = false
    private var isEditingMode = false
    
    enum SortMode { case name, date, size }
    
    init(url: URL) {
        self.currentURL = url
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(FileCell.self, forCellReuseIdentifier: "FileCell")
        tableView.rowHeight = 48
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 0)
        tableView.backgroundColor = .systemBackground
        
        setupNavigation()
        setupSortBar()
        setupBottomBar()
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
    
    private func setupSortBar() {
        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(searchTapped))
        
        let name = UIButton(type: .system)
        name.setTitle("名称", for: .normal)
        name.titleLabel?.font = .systemFont(ofSize: 14)
        name.addTarget(self, action: #selector(sortByName), for: .touchUpInside)
        
        let date = UIButton(type: .system)
        date.setTitle("日期", for: .normal)
        date.titleLabel?.font = .systemFont(ofSize: 14)
        date.addTarget(self, action: #selector(sortByDate), for: .touchUpInside)
        
        let size = UIButton(type: .system)
        size.setTitle("大小", for: .normal)
        size.titleLabel?.font = .systemFont(ofSize: 14)
        size.addTarget(self, action: #selector(sortBySize), for: .touchUpInside)
        
        let listGrid = UIButton(type: .system)
        listGrid.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        listGrid.addTarget(self, action: #selector(toggleView), for: .touchUpInside)
        
        let stack = UIStackView(arrangedSubviews: [name, date, size])
        stack.axis = .horizontal
        stack.spacing = 16
        stack.distribution = .equalSpacing
        
        let container = UIView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -80)
        ])
        
        let sortItem = UIBarButtonItem(customView: container)
        let gridItem = UIBarButtonItem(customView: listGrid)
        
        // 用 tableHeaderView 模拟 Filza 顶部排序栏
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        header.backgroundColor = .secondarySystemBackground
        
        let searchBtn = UIButton(type: .system)
        searchBtn.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchBtn.frame = CGRect(x: 12, y: 10, width: 24, height: 24)
        searchBtn.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        
        name.frame = CGRect(x: 50, y: 10, width: 60, height: 24)
        date.frame = CGRect(x: 120, y: 10, width: 50, height: 24)
        size.frame = CGRect(x: 180, y: 10, width: 50, height: 24)
        
        listGrid.frame = CGRect(x: header.bounds.width - 50, y: 8, width: 36, height: 28)
        
        header.addSubview(searchBtn)
        header.addSubview(name)
        header.addSubview(date)
        header.addSubview(size)
        header.addSubview(listGrid)
        
        tableView.tableHeaderView = header
    }
    
    private func setupBottomBar() {
        let clip = UIBarButtonItem(image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(clipTapped))
        let clock = UIBarButtonItem(image: UIImage(systemName: "clock"), style: .plain, target: self, action: #selector(clockTapped))
        let star = UIBarButtonItem(image: UIImage(systemName: "star"), style: .plain, target: self, action: #selector(starTapped))
        let gear = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(gearTapped))
        let windows = UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: self, action: #selector(windowsTapped))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolbarItems = [clip, flex, clock, flex, star, flex, gear, flex, windows]
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
        case .name:
            items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date:
            items.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .size:
            items.sort { $0.size > $1.size }
        }
    }
    
    private func updateFooter() {
        let count = items.count
        let footer = UILabel()
        footer.text = "/dev/disk1s8   --   \(count) item(s)."
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .secondaryLabel
        footer.textAlignment = .center
        footer.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 32)
        tableView.tableFooterView = footer
    }
    
    @objc private func goBack() { onGoBack?() }
    @objc private func toggleEdit() {
        isEditingMode.toggle()
        tableView.setEditing(isEditingMode, animated: true)
        navigationItem.rightBarButtonItem?.title = isEditingMode ? "完成" : "编辑"
    }
    
    @objc private func sortByName() { sortMode = .name; loadItems() }
    @objc private func sortByDate() { sortMode = .date; loadItems() }
    @objc private func sortBySize() { sortMode = .size; loadItems() }
    @objc private func toggleView() { isGrid.toggle() } // 网格暂未实现
    @objc private func searchTapped() { }
    @objc private func clipTapped() { }
    @objc private func clockTapped() { }
    @objc private func starTapped() { }
    @objc private func gearTapped() { }
    @objc private func windowsTapped() { }
    
    // MARK: Table
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        let item = items[indexPath.row]
        cell.configure(with: item)
        cell.onInfo = { [weak self] in self?.showInfo(item) }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            showInfo(item)
        }
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

// Filza 风格单元格
class FileCell: UITableViewCell {
    private let icon = UIImageView()
    private let nameLabel = UILabel()
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
        infoBtn.translatesAutoresizingMaskIntoConstraints = false
        infoBtn.setImage(UIImage(systemName: "info.circle"), for: .normal)
        infoBtn.addTarget(self, action: #selector(infoTap), for: .touchUpInside)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        
        contentView.addSubview(icon)
        contentView.addSubview(nameLabel)
        contentView.addSubview(infoBtn)
        contentView.addSubview(chevron)
        
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: infoBtn.leadingAnchor, constant: -8),
            
            infoBtn.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
            infoBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            infoBtn.widthAnchor.constraint(equalToConstant: 28),
            infoBtn.heightAnchor.constraint(equalToConstant: 28),
            
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    
    func configure(with item: FileItem) {
        nameLabel.text = item.name
        let cfg = UIImage.SymbolConfiguration(pointSize: 22)
        icon.image = UIImage(systemName: item.isDirectory ? "folder.fill" : "doc.fill", withConfiguration: cfg)
        icon.tintColor = item.isDirectory ? .systemBlue : .systemGray
        chevron.isHidden = !item.isDirectory
    }
    
    @objc private func infoTap() { onInfo?() }
}
