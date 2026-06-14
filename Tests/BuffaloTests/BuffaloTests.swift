import Testing
@testable import Buffalo
import Foundation

@Suite("CacheKey")
struct CacheKeyTests {
    @Test func sameURLProducesSameKey() {
        let url = URL(string: "https://example.com/video.mp4")!
        #expect(CacheKey(url: url) == CacheKey(url: url))
    }

    @Test func differentURLsProduceDifferentKeys() {
        let a = URL(string: "https://example.com/a.mp4")!
        let b = URL(string: "https://example.com/b.mp4")!
        #expect(CacheKey(url: a) != CacheKey(url: b))
    }

    @Test func keyIsHexString() {
        let url = URL(string: "https://example.com/video.mp4")!
        let key = CacheKey(url: url)
        #expect(key.value.allSatisfy { $0.isHexDigit })
        #expect(key.value.count == 64) // SHA-256 → 32 bytes → 64 hex chars
    }
}
