import Foundation

public actor VideoCacheManager {
    public static let shared = VideoCacheManager()

    private let diskCache: DiskCache
    private let downloadManager: VideoDownloadManager

    private init() {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Buffalo", isDirectory: true)
        // Safe: Caches directory always exists on all Apple platforms.
        diskCache = try! DiskCache(directory: dir)
        downloadManager = VideoDownloadManager(
            downloader: VideoDownloadTask(),
            diskCache: diskCache
        )
    }

    init(
        directory: URL,
        downloader: any VideoDownloading = VideoDownloadTask(),
        maxConcurrent: Int = 4
    ) throws {
        diskCache = try DiskCache(directory: directory)
        downloadManager = VideoDownloadManager(
            maxConcurrent: maxConcurrent,
            downloader: downloader,
            diskCache: diskCache
        )
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

        if !options.contains(.forceRefresh),
           let cached = await diskCache.retrieve(forKey: key, fileExtension: ext) {
            return cached
        }

        return try await downloadManager.fetch(
            key: key,
            url: url,
            fileExtension: ext,
            progress: progress
        )
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
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        return await diskCache.retrieve(forKey: key, fileExtension: ext) != nil
    }

    public func clearCache() async throws {
        try await diskCache.clearAll()
    }
}
