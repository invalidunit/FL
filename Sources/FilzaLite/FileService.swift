import Foundation

class FileService {
    static let shared = FileService()
    
    private let fileManager = FileManager.default
    
    private var sandboxRoot: URL {
        documentsURL.deletingLastPathComponent()
    }
    
    var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var trashURL: URL {
        sandboxRoot.appendingPathComponent("Trash")
    }
    
    /// App Group 容器
    var groupURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nan.filzalite")
    }
    
    init() {
        try? fileManager.createDirectory(at: trashURL, withIntermediateDirectories: true)
        if let g = groupURL {
            try? fileManager.createDirectory(at: g, withIntermediateDirectories: true)
        }
    }
    
    func isAllowed(_ url: URL) -> Bool {
        let docs = documentsURL.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        if target == docs || target.hasPrefix(docs + "/") { return true }
        
        let trash = trashURL.standardizedFileURL.path
        if target == trash || target.hasPrefix(trash + "/") { return true }
        
        if let g = groupURL {
            let gp = g.standardizedFileURL.path
            if target == gp || target.hasPrefix(gp + "/") { return true }
        }
        return false
    }
    
    func contents(of url: URL) -> [FileItem] {
        guard isAllowed(url) else { return [] }
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            return urls.compactMap { itemURL -> FileItem? in
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let isDir = values?.isDirectory ?? false
                let size = Int64(values?.fileSize ?? 0)
                let date = values?.contentModificationDate
                
                return FileItem(
                    url: itemURL,
                    name: itemURL.lastPathComponent,
                    isDirectory: isDir,
                    size: size,
                    modificationDate: date,
                    permissions: isDir ? "drwxr-xr-x" : "-rw-r--r--"
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            return []
        }
    }
    
    func createFolder(named name: String, in parent: URL) throws {
        guard isAllowed(parent) else { return }
        let newURL = parent.appendingPathComponent(name)
        try fileManager.createDirectory(at: newURL, withIntermediateDirectories: false)
    }
    
    func createEmptyFile(named name: String, in parent: URL) throws {
        guard isAllowed(parent) else { return }
        let newURL = parent.appendingPathComponent(name)
        try Data().write(to: newURL)
    }
    
    func moveToTrash(item: FileItem) throws {
        let dest = trashURL.appendingPathComponent(item.name)
        let finalDest = uniqueURL(dest)
        try fileManager.moveItem(at: item.url, to: finalDest)
    }
    
    func rename(item: FileItem, to newName: String) throws {
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: item.url, to: newURL)
    }
    
    func copy(item: FileItem, to destination: URL) throws {
        guard isAllowed(destination) else { return }
        let dest = uniqueURL(destination.appendingPathComponent(item.name))
        try fileManager.copyItem(at: item.url, to: dest)
    }
    
    func move(item: FileItem, to destination: URL) throws {
        guard isAllowed(destination) else { return }
        let dest = uniqueURL(destination.appendingPathComponent(item.name))
        try fileManager.moveItem(at: item.url, to: dest)
    }
    
    private func uniqueURL(_ url: URL) -> URL {
        var result = url
        var i = 1
        while fileManager.fileExists(atPath: result.path) {
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let newName = ext.isEmpty ? "\(name) (\(i))" : "\(name) (\(i)).\(ext)"
            result = url.deletingLastPathComponent().appendingPathComponent(newName)
            i += 1
        }
        return result
    }
}
