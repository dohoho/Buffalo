import Testing
@testable import Buffalo
import Foundation

@Suite("VideoDownloadManager")
struct VideoDownloadManagerTests {
    func makeManager(maxConcurrent: Int = 4) throws -> (VideoCacheManager, MockDownloader, URL, URL) {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufCache-\(Int.random(in: 0..<Int.max))")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufTemp-\(Int.random(in: 0..<Int.max))")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let mock = MockDownloader(tempDir: tempDir)
        let manager = try VideoCacheManager(directory: cacheDir, downloader: mock, maxConcurrent: maxConcurrent)
        return (manager, mock, cacheDir, tempDir)
    }

    func makeProgressManager() throws -> (VideoCacheManager, MockProgressDownloader, URL, URL) {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufCache-\(Int.random(in: 0..<Int.max))")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufTemp-\(Int.random(in: 0..<Int.max))")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let mock = MockProgressDownloader(tempDir: tempDir)
        let manager = try VideoCacheManager(directory: cacheDir, downloader: mock)
        return (manager, mock, cacheDir, tempDir)
    }

    @Test func concurrentCallsForSameURLDeduplicateIntoOneDownload() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        await mock.setDelay(.milliseconds(50))

        async let a = manager.video(from: url)
        async let b = manager.video(from: url)
        async let c = manager.video(from: url)
        _ = try await (a, b, c)

        #expect(await mock.callCount == 1)
    }

    @Test func differentURLsDownloadIndependently() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        let url1 = URL(string: "https://example.com/video1.mp4")!
        let url2 = URL(string: "https://example.com/video2.mp4")!

        async let a = manager.video(from: url1)
        async let b = manager.video(from: url2)
        _ = try await (a, b)

        #expect(await mock.callCount == 2)
    }

    @Test func maxConcurrentLimitIsRespected() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager(maxConcurrent: 2)
        defer { cleanup(cacheDir, tempDir) }

        await mock.setDelay(.milliseconds(30))

        let urls = (1...4).map { URL(string: "https://example.com/video\($0).mp4")! }
        try await withThrowingTaskGroup(of: URL.self) { group in
            for url in urls {
                group.addTask { try await manager.video(from: url) }
            }
            for try await _ in group {}
        }

        #expect(await mock.callCount == 4)
        #expect(await mock.peakConcurrency <= 2)
    }

    @Test func cancelInFlightDownloadThrowsCancellationError() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        await mock.setDelay(.milliseconds(100))
        let url = URL(string: "https://example.com/video.mp4")!

        let task = Task { try await manager.video(from: url) }
        try await Task.sleep(for: .milliseconds(10))
        await manager.cancel(url: url)

        let result = await task.result
        #expect(result.isCancellationError)
    }

    @Test func cancelAllStopsAllInFlightDownloads() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        await mock.setDelay(.milliseconds(100))
        let urls = (1...3).map { URL(string: "https://example.com/video\($0).mp4")! }

        let tasks = urls.map { url in Task { try await manager.video(from: url) } }
        try await Task.sleep(for: .milliseconds(10))
        await manager.cancelAll()

        for task in tasks {
            let result = await task.result
            #expect(result.isCancellationError)
        }
    }

    @Test func progressCallbackInvokedInOrder() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeProgressManager()
        defer { cleanup(cacheDir, tempDir) }

        let url = URL(string: "https://example.com/video.mp4")!
        _ = try await manager.video(from: url, progress: { _ in })

        let values = await mock.lastProgressValues
        #expect(!values.isEmpty)
        #expect(values == values.sorted())
        #expect(values.last == 1.0)
    }

    @Test func subsequentDownloadAfterCancelSucceeds() async throws {
        let (manager, mock, cacheDir, tempDir) = try makeManager()
        defer { cleanup(cacheDir, tempDir) }

        await mock.setDelay(.milliseconds(50))
        let url = URL(string: "https://example.com/video.mp4")!

        let cancelled = Task { try await manager.video(from: url) }
        try await Task.sleep(for: .milliseconds(10))
        await manager.cancel(url: url)
        _ = await cancelled.result

        await mock.setDelay(.zero)
        let localURL = try await manager.video(from: url)
        #expect(FileManager.default.fileExists(atPath: localURL.path))
    }

    private func cleanup(_ dirs: URL...) {
        dirs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

extension Result {
    var isCancellationError: Bool {
        guard case .failure(let error) = self else { return false }
        return error is CancellationError
    }
}
