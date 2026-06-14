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
}
