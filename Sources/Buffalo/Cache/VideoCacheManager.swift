import Foundation

public actor VideoCacheManager {
    public static let shared = VideoCacheManager()

    private let diskCache: DiskCache
    private let downloader: any VideoDownloading

    private init() {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Buffalo", isDirectory: true)
        // Safe: Caches directory always exists on all Apple platforms.
        diskCache = try! DiskCache(directory: dir)
        downloader = VideoDownloadTask()
    }

    init(directory: URL, downloader: any VideoDownloading = VideoDownloadTask()) throws {
        diskCache = try DiskCache(directory: directory)
        self.downloader = downloader
    }

    /// Returns a local file URL for the video, downloading it if not already cached.
    @discardableResult
    public func video(from url: URL, options: CacheOptions = .default) async throws -> URL {
        let key = CacheKey(url: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

        if !options.contains(.forceRefresh),
           let cached = await diskCache.retrieve(forKey: key, fileExtension: ext) {
            return cached
        }

        let tempURL = try await downloader.download(from: url)
        return try await diskCache.store(movingFrom: tempURL, forKey: key, fileExtension: ext)
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
