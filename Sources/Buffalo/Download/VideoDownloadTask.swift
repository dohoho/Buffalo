import Foundation

public protocol VideoDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

public protocol VideoDownloadingWithProgress: VideoDownloading {
    func download(from url: URL, progress: @Sendable (Double) -> Void) async throws -> URL
}

struct VideoDownloadTask: VideoDownloadingWithProgress {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(from url: URL) async throws -> URL {
        let (tempURL, response) = try await session.download(from: url)
        try validate(response)
        return tempURL
    }

    func download(from url: URL, progress: @Sendable (Double) -> Void) async throws -> URL {
        let (asyncBytes, response) = try await session.bytes(from: url)
        try validate(response)

        let expectedLength = response.expectedContentLength
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)

        var received: Int64 = 0
        var buffer = Data(capacity: 65_536)

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                received += 1
                if buffer.count >= 65_536 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    if expectedLength > 0 {
                        progress(Double(received) / Double(expectedLength))
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
            try handle.close()
            progress(1.0)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        return tempURL
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VideoCacheError.badServerResponse(statusCode: code)
        }
    }
}
