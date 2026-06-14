public enum VideoCacheError: Error, Sendable, Equatable {
    case invalidURL
    case downloadFailed
    case badServerResponse(statusCode: Int)
    case diskWriteFailed
}
