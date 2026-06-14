import Foundation

public protocol VideoDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

struct VideoDownloadTask: VideoDownloading {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(from url: URL) async throws -> URL {
        let (tempURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VideoCacheError.badServerResponse(statusCode: code)
        }
        return tempURL
    }
}
