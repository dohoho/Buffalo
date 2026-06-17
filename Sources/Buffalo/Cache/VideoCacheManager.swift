import Foundation

public actor VideoCacheManager {
    public static let shared = VideoCacheManager()

    private let diskCache: DiskCache
    private let memoryCache: MemoryCache
    private let downloadManager: VideoDownloadManager

    private init() {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Buffalo", isDirectory: true)
        // Safe: Caches directory always exists on all Apple platforms.
        diskCache = try! DiskCache(directory: dir)
        memoryCache = MemoryCache()
        downloadManager = VideoDownloadManager(
            downloader: VideoDownloadTask(),
            diskCache: diskCache
        )
    }

    init(
        directory: URL,
        downloader: any VideoDownloading = VideoDownloadTask(),
        maxConcurrent: Int = 4,
        memoryCacheCountLimit: Int = 20,
        diskCacheConfig: DiskCacheConfig = DiskCacheConfig()
    ) throws {
        diskCache = try DiskCache(directory: directory, config: diskCacheConfig)
        memoryCache = MemoryCache(countLimit: memoryCacheCountLimit)
        downloadManager = VideoDownloadManager(
            maxConcurrent: maxConcurrent,
            downloader: downloader,
            diskCache: diskCache
        )
    }

    public var diskCacheConfig: DiskCacheConfig {
        get async { await diskCache.config }
    }

    public func configure(diskCache config: DiskCacheConfig) async {
        await diskCache.updateConfig(config)
    }

    /// Returns a local file URL for the video, downloading it if not already cached.
    @discardableResult
    public func video(
        from url: URL,
        options: CacheOptions = .default,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let key = CacheKey(url: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

        if !options.contains(.forceRefresh) {
            if options.contains(.memoryCache), let cached = memoryCache.retrieve(forKey: key) {
                return cached
            }
            if let cached = await diskCache.retrieve(forKey: key, fileExtension: ext) {
                if options.contains(.memoryCache) {
                    memoryCache.store(url: cached, forKey: key)
                }
                return cached
            }
        }

        let result = try await downloadManager.fetch(
            key: key,
            url: url,
            fileExtension: ext,
            progress: progress
        )

        if options.contains(.memoryCache) {
            memoryCache.store(url: result, forKey: key)
        }

        return result
    }

    public func cancel(url: URL) async {
        let key = CacheKey(url: url)
        await downloadManager.cancel(key: key)
    }

    public func cancelAll() async {
        await downloadManager.cancelAll()
    }

    public func isCached(url: URL) async -> Bool {
        let key = CacheKey(url: url)
        if memoryCache.retrieve(forKey: key) != nil { return true }
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        return await diskCache.retrieve(forKey: key, fileExtension: ext) != nil
    }

    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    public func clearDiskCache() async throws {
        try await diskCache.clearAll()
        memoryCache.removeAll()
    }

    public func clearCache() async throws {
        try await clearDiskCache()
    }

    public func diskCacheSize() async throws -> Int {
        try await diskCache.totalSize()
    }
}
