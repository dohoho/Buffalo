public struct CacheOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let diskCache = CacheOptions(rawValue: 1 << 0)
    public static let forceRefresh = CacheOptions(rawValue: 1 << 1)

    public static let `default`: CacheOptions = [.diskCache]
}
