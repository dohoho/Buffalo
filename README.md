<p align="center">
  <img src="images/buffalo-banner.png" alt="Buffalo" />
</p>

<p align="center">
  <a href="https://swift.org/package-manager">
    <img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="Swift Package Manager" />
  </a>
  <a href="https://swift.org">
    <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6.0" />
  </a>
  <img src="https://img.shields.io/badge/iOS-16.6%2B-blue.svg" alt="iOS 16.6+" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" alt="MIT License" />
</p>

---

Buffalo is a lightweight, Kingfisher-inspired video caching library for iOS. It downloads videos asynchronously, caches them to disk, and returns a local file URL ready to hand off to `AVPlayer` — with zero configuration required to get started.

## Features

- **Async/await API** — no completion handlers, no delegates
- **Disk cache** — persists videos across app launches, keyed by SHA-256 hash of the URL
- **Actor-based concurrency** — thread-safe by design, Swift 6 strict concurrency compliant
- **Force refresh** — bypass cache and re-download when needed
- **No external dependencies** — Foundation only

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS | 16.6+ |
| macOS | 13.0+ |
| Swift | 6.0+ |
| Xcode | 16+ |

## Installation

### Swift Package Manager

Add Buffalo to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dohoho/Buffalo.git", from: "1.0.0")
]
```

Or add it via Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Usage

### Basic — download and cache

```swift
import Buffalo

let localURL = try await VideoCacheManager.shared.video(from: remoteURL)

// Pass directly to AVPlayer
let player = AVPlayer(url: localURL)
```

### Check cache before playing

```swift
let isCached = await VideoCacheManager.shared.isCached(url: remoteURL)
```

### Force re-download

```swift
let localURL = try await VideoCacheManager.shared.video(
    from: remoteURL,
    options: .forceRefresh
)
```

### Clear cache

```swift
try await VideoCacheManager.shared.clearCache()
```

### Custom cache directory

```swift
let customDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("MyVideoCache")

let cache = try VideoCacheManager(directory: customDir)
let localURL = try await cache.video(from: remoteURL)
```

## How It Works

```
URL ──► Cache hit? ──yes──► Return local URL
             │
             no
             │
             ▼
        URLSession.download()
             │
             ▼
        Move temp file → Disk cache
             │
             ▼
        Return local URL
```

1. A `CacheKey` is derived from the video URL using SHA-256.
2. `DiskCache` checks if a file with that key exists in the cache directory.
3. On a miss, `VideoDownloadTask` downloads the video via `URLSession` directly to a temporary file (no memory pressure from large files).
4. The temporary file is moved atomically into the cache directory.
5. The local `URL` is returned — ready for `AVPlayer`.

## Architecture

```
Sources/Buffalo/
├── Cache/
│   ├── VideoCacheManager.swift   — public API, main coordinator
│   └── DiskCache.swift           — file storage, key-based lookup
├── Download/
│   └── VideoDownloadTask.swift   — single URLSession download
└── Models/
    ├── CacheKey.swift            — SHA-256 URL → cache key
    ├── CacheOptions.swift        — option flags (diskCache, forceRefresh)
    └── VideoCacheError.swift     — typed errors
```

## License

Buffalo is released under the MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">Inspired by <a href="https://github.com/onevcat/Kingfisher">Kingfisher</a> — but for video.</p>
