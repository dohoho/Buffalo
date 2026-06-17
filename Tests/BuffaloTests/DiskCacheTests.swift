import Testing
@testable import Buffalo
import Foundation

@Suite("DiskCache")
struct DiskCacheTests {
    // Each test gets a unique temp directory to avoid cross-test pollution.
    func makeCache() throws -> (DiskCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuffaloTests-\(Int.random(in: 0..<Int.max))")
        let cache = try DiskCache(directory: dir)
        return (cache, dir)
    }

    func writeTempFile(content: Data = Data("fake".utf8), dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("source.mp4")
        try content.write(to: file)
        return file
    }

    @Test func storeCreatesFileAtExpectedLocation() async throws {
        let (cache, cacheDir) = try makeCache()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        let key = CacheKey(url: url)
        let tempFile = try writeTempFile(dir: tmpDir)

        let stored = try await cache.store(movingFrom: tempFile, forKey: key, fileExtension: "mp4")
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func retrieveReturnsNilForCacheMiss() async throws {
        let (cache, cacheDir) = try makeCache()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let url = URL(string: "https://example.com/missing.mp4")!
        let key = CacheKey(url: url)
        let result = await cache.retrieve(forKey: key, fileExtension: "mp4")
        #expect(result == nil)
    }

    @Test func retrieveReturnsURLAfterStore() async throws {
        let (cache, cacheDir) = try makeCache()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        let key = CacheKey(url: url)
        let tempFile = try writeTempFile(dir: tmpDir)

        _ = try await cache.store(movingFrom: tempFile, forKey: key, fileExtension: "mp4")
        let retrieved = await cache.retrieve(forKey: key, fileExtension: "mp4")
        #expect(retrieved != nil)
    }

    @Test func clearAllRemovesAllFiles() async throws {
        let (cache, cacheDir) = try makeCache()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        let key = CacheKey(url: url)
        let tempFile = try writeTempFile(dir: tmpDir)
        _ = try await cache.store(movingFrom: tempFile, forKey: key, fileExtension: "mp4")

        try await cache.clearAll()

        let retrieved = await cache.retrieve(forKey: key, fileExtension: "mp4")
        #expect(retrieved == nil)
    }

    @Test func removeDeletesSpecificFile() async throws {
        let (cache, cacheDir) = try makeCache()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        let key = CacheKey(url: url)
        let tempFile = try writeTempFile(dir: tmpDir)
        _ = try await cache.store(movingFrom: tempFile, forKey: key, fileExtension: "mp4")

        try await cache.remove(forKey: key, fileExtension: "mp4")

        let retrieved = await cache.retrieve(forKey: key, fileExtension: "mp4")
        #expect(retrieved == nil)
    }

    // MARK: - DiskCacheConfig

    @Test func defaultSizeLimitIs500MB() async throws {
        let (cache, cacheDir) = try makeCache()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let config = await cache.config
        #expect(config.sizeLimit == 500_000_000)
    }

    @Test func updateConfigChangesSizeLimit() async throws {
        let (cache, cacheDir) = try makeCache()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        await cache.updateConfig(DiskCacheConfig(sizeLimit: 2_000_000_000))

        let config = await cache.config
        #expect(config.sizeLimit == 2_000_000_000)
    }

    @Test func evictsOldestFileWhenOverSizeLimit() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvictTest-\(Int.random(in: 0..<Int.max))")
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvictSrc-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: dir) }
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Limit: 80 bytes; each file: 50 bytes → second store triggers eviction of the first.
        let cache = try DiskCache(directory: dir, config: DiskCacheConfig(sizeLimit: 80))

        let keyA = CacheKey(url: URL(string: "https://example.com/a.mp4")!)
        let keyB = CacheKey(url: URL(string: "https://example.com/b.mp4")!)

        let fileA = tmpDir.appendingPathComponent("a.mp4")
        try Data(repeating: 0, count: 50).write(to: fileA)
        let storedA = try await cache.store(movingFrom: fileA, forKey: keyA, fileExtension: "mp4")

        // Mark A as older so LRU eviction picks it first.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)],
            ofItemAtPath: storedA.path
        )

        let fileB = tmpDir.appendingPathComponent("b.mp4")
        try Data(repeating: 0, count: 50).write(to: fileB)
        _ = try await cache.store(movingFrom: fileB, forKey: keyB, fileExtension: "mp4")

        #expect(await cache.retrieve(forKey: keyA, fileExtension: "mp4") == nil)
        #expect(await cache.retrieve(forKey: keyB, fileExtension: "mp4") != nil)
    }

    @Test func noEvictionWhenSizeLimitIsZero() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnlimitedTest-\(Int.random(in: 0..<Int.max))")
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnlimitedSrc-\(Int.random(in: 0..<Int.max))")
        defer { try? FileManager.default.removeItem(at: dir) }
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let cache = try DiskCache(directory: dir, config: DiskCacheConfig(sizeLimit: 0))

        let keys = (0..<5).map { CacheKey(url: URL(string: "https://example.com/v\($0).mp4")!) }
        for (i, key) in keys.enumerated() {
            let file = tmpDir.appendingPathComponent("v\(i).mp4")
            try Data(repeating: UInt8(i), count: 100).write(to: file)
            _ = try await cache.store(movingFrom: file, forKey: key, fileExtension: "mp4")
        }

        for key in keys {
            #expect(await cache.retrieve(forKey: key, fileExtension: "mp4") != nil)
        }
    }
}
