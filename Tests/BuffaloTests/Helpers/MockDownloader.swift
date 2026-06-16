import Foundation
@testable import Buffalo

actor MockDownloader: VideoDownloading {
    private(set) var callCount = 0
    private(set) var peakConcurrency = 0
    private var currentConcurrency = 0
    private var failing = false
    private let tempDir: URL
    private var delay: Duration = .zero

    init(tempDir: URL) {
        self.tempDir = tempDir
    }

    func setFailing(_ value: Bool) {
        failing = value
    }

    func setDelay(_ value: Duration) {
        delay = value
    }

    func download(from url: URL) async throws -> URL {
        callCount += 1
        currentConcurrency += 1
        peakConcurrency = max(peakConcurrency, currentConcurrency)
        defer { currentConcurrency -= 1 }
        let myCount = callCount

        guard !failing else { throw VideoCacheError.downloadFailed }
        if delay != .zero { try await Task.sleep(for: delay) }
        let file = tempDir.appendingPathComponent("\(myCount).mp4")
        try Data("fake video bytes".utf8).write(to: file)
        return file
    }
}

actor MockProgressDownloader: VideoDownloadingWithProgress {
    private(set) var callCount = 0
    private(set) var lastProgressValues: [Double] = []
    private let tempDir: URL
    var chunks: Int = 4

    init(tempDir: URL) {
        self.tempDir = tempDir
    }

    func download(from url: URL) async throws -> URL {
        try await download(from: url, progress: { _ in })
    }

    func download(from url: URL, progress: @Sendable (Double) -> Void) async throws -> URL {
        callCount += 1
        let file = tempDir.appendingPathComponent("\(callCount).mp4")
        try Data("fake video bytes".utf8).write(to: file)
        var captured: [Double] = []
        for i in 1...chunks {
            let fraction = Double(i) / Double(chunks)
            progress(fraction)
            captured.append(fraction)
            await Task.yield()
        }
        lastProgressValues = captured
        return file
    }
}
