import Foundation

class FileService {
    static let shared = FileService()
    
    private let fileManager = FileManager.default
    
    var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var libraryURL: URL {
        documentsURL.deletingLastPathComponent().appendingPathComponent("Library")
    }
    
    var trashURL: URL {
        libraryURL.appendingPathComponent("Trash")
    }
    
    var cachesURL: URL {
        libraryURL.appendingPathComponent("Caches")
    }
    
    var groupURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nan.filzalite")
    }
    
    init() {
        createTrashIfNeeded()
        if let g = groupURL {
            try? fileManager.createDirectory(at: g, withIntermediateDirectories: true)
        }
    }
    
    func createTrashIfNeeded() {
        if !fileManager.fileExists(atPath: trashURL.path) {
            try? fileManager.createDirectory(at: trashURL, withIntermediateDirectories: true)
        }
    }
    
    func isAllowed(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        
        let roots = [
            documentsURL.standardizedFileURL.path,
            trashURL.standardizedFileURL.path,
            cachesURL.standardizedFileURL.path
        ]
        
        for r in roots {
            if target == r || target.hasPrefix(r + "/") { return true }
        }
        
        if let g = groupURL {
            let gp = g.standardizedFileURL.path
            if target == gp || target.hasPrefix(gp + "/") { return true }
        }
        return false
    }
    
    func contents(of url: URL) -> [FileItem] {
        createTrashIfNeeded()
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
        createTrashIfNeeded()
        guard isAllowed(parent) else { return }
        let newURL = parent.appendingPathComponent(name)
        try fileManager.createDirectory(at: newURL, withIntermediateDirectories: false)
    }
    
    func createEmptyFile(named name: String, in parent: URL) throws {
        createTrashIfNeeded()
        guard isAllowed(parent) else { return }
        let newURL = parent.appendingPathComponent(name)
        try Data().write(to: newURL)
    }
    
    func moveToTrash(item: FileItem) throws {
        createTrashIfNeeded()
        let dest = trashURL.appendingPathComponent(item.name)
        let finalDest = uniqueURL(dest)
        try fileManager.moveItem(at: item.url, to: finalDest)
    }
    
    func deletePermanently(item: FileItem) throws {
        try fileManager.removeItem(at: item.url)
    }
    
    func clearCaches() throws {
        if fileManager.fileExists(atPath: cachesURL.path) {
            try fileManager.removeItem(at: cachesURL)
        }
        try fileManager.createDirectory(at: cachesURL, withIntermediateDirectories: true)
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
