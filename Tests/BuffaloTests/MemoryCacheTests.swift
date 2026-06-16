import Testing
@testable import Buffalo
import Foundation

@Suite("MemoryCache")
struct MemoryCacheTests {
    let url = URL(string: "https://example.com/video.mp4")!

    func makeManager() throws -> (VideoCacheManager, MockDownloader, URL, URL) {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufCache-\(Int.random(in: 0..<Int.max))")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufTemp-\(Int.random(in: 0..<Int.max))")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let mock = MockDownloader(tempDir: tempDir)
        let manager = try VideoCacheManager(directory: cacheDir, downloader: mock)
        return (manager, mock, cacheDir, tempDir)
    }

    @Test func memoryCacheHitSkipsDownloadAndDiskLookup() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        _ = try await manager.video(from: url)
        _ = try await manager.video(from: url)
        _ = try await manager.video(from: url)

        #expect(await mock.callCount == 1)
    }

    @Test func clearMemoryCacheForcesNextCallToHitDisk() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        _ = try await manager.video(from: url)
        await manager.clearMemoryCache()
        _ = try await manager.video(from: url)

        #expect(await mock.callCount == 1)
    }

    @Test func forceRefreshSkipsMemoryCache() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        _ = try await manager.video(from: url)
        _ = try await manager.video(from: url, options: .forceRefresh)

        #expect(await mock.callCount == 2)
    }

    @Test func memoryCacheOptionOffSkipsMemoryStore() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        _ = try await manager.video(from: url, options: .diskCache)
        _ = try await manager.video(from: url, options: .diskCache)

        #expect(await mock.callCount == 1)
    }

    @Test func diskCacheSizeReturnsPositiveAfterDownload() async throws {
        let (manager, _, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        _ = try await manager.video(from: url)
        let size = try await manager.diskCacheSize()
        #expect(size > 0)
    }

    @Test func clearDiskCacheAlsoClearsMemoryCache() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        _ = try await manager.video(from: url)
        try await manager.clearDiskCache()
        _ = try await manager.video(from: url)

        #expect(await mock.callCount == 2)
    }

    private func cleanup(_ dirs: URL...) {
        dirs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
