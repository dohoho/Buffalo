import Testing
@testable import Buffalo
import Foundation

@Suite("VideoCacheManager")
struct VideoCacheManagerTests {
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

    @Test func cacheMissDownloadsVideo() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        let localURL = try await manager.video(from: url)

        #expect(await mock.callCount == 1)
        #expect(FileManager.default.fileExists(atPath: localURL.path))
    }

    @Test func cacheHitSkipsDownload() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        _ = try await manager.video(from: url)
        _ = try await manager.video(from: url)

        #expect(await mock.callCount == 1)
    }

    @Test func forceRefreshBypassesCache() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        _ = try await manager.video(from: url)
        _ = try await manager.video(from: url, options: .forceRefresh)

        #expect(await mock.callCount == 2)
    }

    @Test func isCachedReturnsFalseBeforeFirstDownload() async throws {
        let (manager, _, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        #expect(await manager.isCached(url: url) == false)
    }

    @Test func isCachedReturnsTrueAfterDownload() async throws {
        let (manager, _, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        _ = try await manager.video(from: url)

        #expect(await manager.isCached(url: url) == true)
    }

    @Test func downloadFailurePropagatesError() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await mock.setFailing(true)
        let url = URL(string: "https://example.com/video.mp4")!

        await #expect(throws: VideoCacheError.downloadFailed) {
            _ = try await manager.video(from: url)
        }
    }

    @Test func clearCacheRemovesAllFiles() async throws {
        let (manager, _, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        _ = try await manager.video(from: url)
        try await manager.clearCache()

        #expect(await manager.isCached(url: url) == false)
    }

    // MARK: - DiskCacheConfig

    @Test func diskCacheConfigReturnsDefault() async throws {
        let (manager, _, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = await manager.diskCacheConfig
        #expect(config.sizeLimit == 500_000_000)
    }

    @Test func configureDiskCacheUpdatesConfig() async throws {
        let (manager, _, cacheDir, tempDir) = try makeManager()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.configure(diskCache: DiskCacheConfig(sizeLimit: 1_000_000_000))

        let config = await manager.diskCacheConfig
        #expect(config.sizeLimit == 1_000_000_000)
    }

    @Test func customDiskCacheConfigIsAppliedAtInit() async throws {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufCache-\(Int.random(in: 0..<Int.max))")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufTemp-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let mock = MockDownloader(tempDir: tempDir)
        let manager = try VideoCacheManager(
            directory: cacheDir,
            downloader: mock,
            diskCacheConfig: DiskCacheConfig(sizeLimit: 0)
        )

        let config = await manager.diskCacheConfig
        #expect(config.sizeLimit == 0)
    }
}
