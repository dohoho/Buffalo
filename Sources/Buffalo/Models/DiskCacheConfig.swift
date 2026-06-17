import Foundation

public struct DiskCacheConfig: Sendable {
    /// Maximum disk usage in bytes. `0` means unlimited. Default is 500 MB.
    public var sizeLimit: Int

    public init(sizeLimit: Int = 500_000_000) {
        self.sizeLimit = sizeLimit
    }
}
