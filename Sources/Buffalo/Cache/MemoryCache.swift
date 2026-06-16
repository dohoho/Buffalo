import Foundation

final class MemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSURL>()

    init(countLimit: Int = 20) {
        cache.countLimit = countLimit
    }

    func store(url: URL, forKey key: CacheKey) {
        cache.setObject(url as NSURL, forKey: key.value as NSString)
    }

    func retrieve(forKey key: CacheKey) -> URL? {
        cache.object(forKey: key.value as NSString) as? URL
    }

    func remove(forKey key: CacheKey) {
        cache.removeObject(forKey: key.value as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
