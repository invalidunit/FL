import Foundation

class FileService {
    static let shared = FileService()
    
    private let fileManager = FileManager.default
    
    /// 获取沙盒 Documents 目录（非越狱环境安全起点）
    var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func contents(of url: URL) -> [FileItem] {
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
                
                // 简单权限字符串（真实场景可扩展）
                let perms = isDir ? "drwxr-xr-x" : "-rw-r--r--"
                
                return FileItem(
                    url: itemURL,
                    name: itemURL.lastPathComponent,
                    isDirectory: isDir,
                    size: size,
                    modificationDate: date,
                    permissions: perms
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            print("读取目录失败: \(error)")
            return []
        }
    }
    
    func createFolder(named name: String, in parent: URL) throws {
        let newURL = parent.appendingPathComponent(name)
        try fileManager.createDirectory(at: newURL, withIntermediateDirectories: false)
    }
    
    func delete(item: FileItem) throws {
        try fileManager.removeItem(at: item.url)
    }
    
    func rename(item: FileItem, to newName: String) throws {
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: item.url, to: newURL)
    }
}
