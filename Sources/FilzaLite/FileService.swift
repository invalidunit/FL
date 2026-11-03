    func deletePermanently(item: FileItem) throws {
        try fileManager.removeItem(at: item.url)
    }
    
    func clearCaches() throws {
        if fileManager.fileExists(atPath: cachesURL.path) {
            try fileManager.removeItem(at: cachesURL)
        }
        try fileManager.createDirectory(at: cachesURL, withIntermediateDirectories: true)
    }