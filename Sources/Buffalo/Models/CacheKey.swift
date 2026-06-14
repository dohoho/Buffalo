import Foundation
import CryptoKit

public struct CacheKey: Hashable, Sendable {
    public let value: String

    public init(url: URL) {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        value = digest.map { String(format: "%02x", $0) }.joined()
    }
}
