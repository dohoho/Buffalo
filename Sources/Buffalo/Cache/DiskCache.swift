import Foundation

actor DiskCache {
    private let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func store(movingFrom tempURL: URL, forKey key: CacheKey, fileExtension ext: String) throws -> URL {
        let destination = cachedFileURL(for: key, ext: ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    func retrieve(forKey key: CacheKey, fileExtension ext: String) -> URL? {
        let url = cachedFileURL(for: key, ext: ext)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func remove(forKey key: CacheKey, fileExtension ext: String) throws {
        let url = cachedFileURL(for: key, ext: ext)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func clearAll() throws {
        let items = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        for item in items {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func cachedFileURL(for key: CacheKey, ext: String) -> URL {
        directory.appendingPathComponent(key.value).appendingPathExtension(ext)
    }
}
