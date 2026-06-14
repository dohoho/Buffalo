import Foundation
@testable import Buffalo

actor MockDownloader: VideoDownloading {
    private(set) var callCount = 0
    private var failing = false
    private let tempDir: URL

    init(tempDir: URL) {
        self.tempDir = tempDir
    }

    func setFailing(_ value: Bool) {
        failing = value
    }

    func download(from url: URL) async throws -> URL {
        callCount += 1
        guard !failing else { throw VideoCacheError.downloadFailed }
        // Each call writes a fresh file so the move in DiskCache always finds a source.
        let file = tempDir.appendingPathComponent("\(callCount).mp4")
        try Data("fake video bytes".utf8).write(to: file)
        return file
    }
}
