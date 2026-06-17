import Foundation

actor DiskCache {
    private let directory: URL
    var config: DiskCacheConfig

    init(directory: URL, config: DiskCacheConfig = DiskCacheConfig()) throws {
        self.directory = directory
        self.config = config
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func updateConfig(_ config: DiskCacheConfig) {
        self.config = config
    }

    func store(movingFrom tempURL: URL, forKey key: CacheKey, fileExtension ext: String) throws -> URL {
        let destination = cachedFileURL(for: key, ext: ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        if config.sizeLimit > 0 {
            try evictIfNeeded()
        }
        return destination
    }

    func retrieve(forKey key: CacheKey, fileExtension ext: String) -> URL? {
        let url = cachedFileURL(for: key, ext: ext)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // LRU: bump modification date so this file is treated as recently used during eviction.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
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

    func totalSize() throws -> Int {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let items = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        )
        return try items.reduce(0) { sum, url in
            let size = try url.resourceValues(forKeys: keys).fileSize ?? 0
            return sum + size
        }
    }

    private func cachedFileURL(for key: CacheKey, ext: String) -> URL {
        directory.appendingPathComponent(key.value).appendingPathExtension(ext)
    }

    private func evictIfNeeded() throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let items = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        )

        var totalSize = 0
        var fileInfos: [(url: URL, size: Int, date: Date)] = []

        for item in items {
            let resources = try item.resourceValues(forKeys: keys)
            let size = resources.fileSize ?? 0
            let date = resources.contentModificationDate ?? .distantPast
            totalSize += size
            fileInfos.append((url: item, size: size, date: date))
        }

        guard totalSize > config.sizeLimit else { return }

        // LRU: sort oldest modification date first — evict least recently used files until under limit.
        for info in fileInfos.sorted(by: { $0.date < $1.date }) {
            guard totalSize > config.sizeLimit else { break }
            try FileManager.default.removeItem(at: info.url)
            totalSize -= info.size
        }
    }
}
