//
//  CacheTestView.swift
//  Buffalo-iOS
//

import SwiftUI
import AVKit
import Buffalo

// MARK: - Test data

struct TestVideo: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL

    // Public domain videos — W3Schools & Blender Foundation open movies
    static let samples: [TestVideo] = [
        TestVideo(
            name: "W3Schools · mov_bbb (~1MB)",
            url: URL(string: "https://www.w3schools.com/html/mov_bbb.mp4")!
        ),
        TestVideo(
            name: "W3Schools · movie (~1MB)",
            url: URL(string: "https://www.w3schools.com/html/movie.mp4")!
        ),
        TestVideo(
            name: "Big Buck Bunny 320p (~60MB)",
            url: URL(string: "https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4")!
        ),
        TestVideo(
            name: "Big Buck Bunny 640p (~120MB)",
            url: URL(string: "https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_640x360.mp4")!
        ),
    ]
}

// MARK: - ViewModel

@MainActor
@Observable
final class CacheTestViewModel {

    enum Status {
        case idle
        case downloading
        case cached(url: URL, size: String)
        case failed(String)

        var label: String {
            switch self {
            case .idle:                return "Not cached"
            case .downloading:         return "Downloading…"
            case .cached(_, let size): return "Cached · \(size)"
            case .failed(let msg):     return msg
            }
        }

        var color: Color {
            switch self {
            case .idle:        return .secondary
            case .downloading: return .orange
            case .cached:      return .green
            case .failed:      return .red
            }
        }

        var cachedURL: URL? {
            guard case .cached(let url, _) = self else { return nil }
            return url
        }

        var isIdle: Bool {
            guard case .idle = self else { return false }
            return true
        }
    }

    private(set) var statuses: [UUID: Status] = [:]
    private(set) var logs: [String] = []
    var isClearing = false

    func status(for video: TestVideo) -> Status {
        statuses[video.id] ?? .idle
    }

    // MARK: - Actions

    func download(_ video: TestVideo) {
        guard status(for: video).isIdle else { return }
        set(.downloading, for: video)
        Task {
            let start = Date()
            do {
                let wasCached = await VideoCacheManager.shared.isCached(url: video.url)
                let localURL  = try await VideoCacheManager.shared.video(from: video.url)
                let elapsed   = Date().timeIntervalSince(start)
                let size      = fileSize(at: localURL)
                set(.cached(url: localURL, size: size), for: video)
                let source = wasCached ? "CACHE HIT" : "downloaded"
                append("✅ \(video.name) — \(source) in \(String(format: "%.2f", elapsed))s (\(size))")
            } catch {
                set(.failed(error.localizedDescription), for: video)
                append("❌ \(video.name) — \(error.localizedDescription)")
            }
        }
    }

    func checkAll(_ videos: [TestVideo]) {
        Task {
            for video in videos {
                let hit = await VideoCacheManager.shared.isCached(url: video.url)
                if hit, let localURL = try? await VideoCacheManager.shared.video(from: video.url) {
                    set(.cached(url: localURL, size: fileSize(at: localURL)), for: video)
                    append("🎯 CACHED: \(video.name) (\(fileSize(at: localURL)))")
                } else {
                    append("💨 NOT CACHED: \(video.name)")
                }
            }
        }
    }

    func redownload(_ video: TestVideo) {
        statuses[video.id] = .idle
        download(video)
    }

    func clearAll(_ videos: [TestVideo]) {
        Task {
            isClearing = true
            defer { isClearing = false }
            do {
                try await VideoCacheManager.shared.clearCache()
                for video in videos { statuses[video.id] = nil }
                append("🗑️ Cache cleared")
            } catch {
                append("❌ Clear failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func set(_ status: Status, for video: TestVideo) {
        statuses[video.id] = status
    }

    private func append(_ message: String) {
        logs.insert(message, at: 0)
        if logs.count > 40 { logs = Array(logs.prefix(40)) }
    }

    private func fileSize(at url: URL) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - CacheTestView

struct CacheTestView: View {
    @State private var vm = CacheTestViewModel()
    @State private var playingURL: IdentifiableURL?

    private let videos = TestVideo.samples

    var body: some View {
        NavigationStack {
            List {
                Section("Test Videos") {
                    ForEach(videos) { video in
                        VideoRow(
                            video: video,
                            status: vm.status(for: video),
                            onDownload: { vm.download(video) },
                            onRedownload: { vm.redownload(video) },
                            onPlay: {
                                if let url = vm.status(for: video).cachedURL {
                                    playingURL = IdentifiableURL(url: url)
                                }
                            }
                        )
                    }
                }

                if !vm.logs.isEmpty {
                    Section("Log") {
                        ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Buffalo Cache")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Check All") { vm.checkAll(videos) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear Cache", role: .destructive) { vm.clearAll(videos) }
                        .disabled(vm.isClearing)
                }
            }
        }
        .fullScreenCover(item: $playingURL) { item in
            PlayerSheet(url: item.url)
        }
        .onAppear { vm.checkAll(videos) }
    }
}

// MARK: - VideoRow

struct VideoRow: View {
    let video: TestVideo
    let status: CacheTestViewModel.Status
    let onDownload: () -> Void
    let onRedownload: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.name)
                .font(.headline)

            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }

            HStack(spacing: 10) {
                switch status {
                case .idle:
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                case .downloading:
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .cached:
                    Button(action: onRedownload) {
                        Label("Re-download", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)

                case .failed:
                    Button(action: onDownload) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PlayerSheet

struct PlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(.systemGray3))
                    .padding()
            }
        }
    }
}

// MARK: - Helpers

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
