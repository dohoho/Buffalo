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

    enum CacheSource {
        case memory, disk, network

        var label: String {
            switch self {
            case .memory:  return "Memory hit"
            case .disk:    return "Disk hit"
            case .network: return "Downloaded"
            }
        }

        var icon: String {
            switch self {
            case .memory:  return "memorychip"
            case .disk:    return "internaldrive"
            case .network: return "arrow.down.circle"
            }
        }
    }

    enum Status {
        case idle
        case downloading(progress: Double)
        case cached(url: URL, size: String, source: CacheSource)
        case failed(String)

        var label: String {
            switch self {
            case .idle:                           return "Not cached"
            case .downloading(let p):             return p > 0 ? "Downloading \(Int(p * 100))%" : "Downloading…"
            case .cached(_, let size, let src):   return "\(src.label) · \(size)"
            case .failed(let msg):                return msg
            }
        }

        var color: Color {
            switch self {
            case .idle:                     return .secondary
            case .downloading:              return .orange
            case .cached(_, _, let src):
                switch src {
                case .memory:  return .purple
                case .disk:    return .blue
                case .network: return .green
                }
            case .failed: return .red
            }
        }

        var cachedURL: URL? {
            guard case .cached(let url, _, _) = self else { return nil }
            return url
        }

        var isIdle: Bool {
            guard case .idle = self else { return false }
            return true
        }

        var downloadProgress: Double? {
            guard case .downloading(let p) = self else { return nil }
            return p
        }
    }

    private(set) var statuses: [UUID: Status] = [:]
    private(set) var logs: [String] = []
    private(set) var diskCacheSize: String = "—"
    var isClearing = false

    func status(for video: TestVideo) -> Status {
        statuses[video.id] ?? .idle
    }

    // MARK: - Actions

    func download(_ video: TestVideo) {
        guard status(for: video).isIdle else { return }
        set(.downloading(progress: 0), for: video)
        Task {
            let start = Date()
            do {
                let localURL = try await VideoCacheManager.shared.video(from: video.url) { [weak self] p in
                    Task { @MainActor [weak self] in
                        self?.set(.downloading(progress: p), for: video)
                    }
                }
                let elapsed = Date().timeIntervalSince(start)
                let size = fileSize(at: localURL)
                let source = cacheSource(elapsed: elapsed)
                set(.cached(url: localURL, size: size, source: source), for: video)
                append("✅ \(video.name) — \(source.label) in \(String(format: "%.3f", elapsed))s (\(size))")
                await refreshDiskSize()
            } catch {
                set(.idle, for: video)
                append("❌ \(video.name) — \(error.localizedDescription)")
            }
        }
    }

    func redownload(_ video: TestVideo) {
        statuses[video.id] = .idle
        download(video)
    }

    func checkAll(_ videos: [TestVideo]) {
        Task {
            for video in videos {
                let start = Date()
                guard let localURL = try? await VideoCacheManager.shared.video(from: video.url) else { continue }
                let elapsed = Date().timeIntervalSince(start)
                let size = fileSize(at: localURL)
                let source = cacheSource(elapsed: elapsed)
                set(.cached(url: localURL, size: size, source: source), for: video)
            }
            await refreshDiskSize()
        }
    }

    func clearMemoryCache() {
        Task { await VideoCacheManager.shared.clearMemoryCache() }
        append("🧠 Memory cache cleared")
        // Reset any cached status to disk (still on disk, just not in memory)
        for (id, status) in statuses {
            if case .cached(let url, let size, _) = status {
                statuses[id] = .cached(url: url, size: size, source: .disk)
            }
        }
    }

    func clearAll(_ videos: [TestVideo]) {
        Task {
            isClearing = true
            defer { isClearing = false }
            do {
                try await VideoCacheManager.shared.clearCache()
                for video in videos { statuses[video.id] = nil }
                diskCacheSize = "0 bytes"
                append("🗑️ All cache cleared (memory + disk)")
            } catch {
                append("❌ Clear failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshDiskSize() async {
        let bytes = (try? await VideoCacheManager.shared.diskCacheSize()) ?? 0
        diskCacheSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Private

    private func cacheSource(elapsed: TimeInterval) -> CacheSource {
        if elapsed < 0.005 { return .memory }
        if elapsed < 0.200 { return .disk }
        return .network
    }

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
                Section {
                    HStack {
                        Label("Disk usage", systemImage: "internaldrive")
                        Spacer()
                        Text(vm.diskCacheSize)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Cache Stats")
                }

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
                    Menu {
                        Button("Check All") { vm.checkAll(videos) }
                        Button("Clear Memory Cache") { vm.clearMemoryCache() }
                        Button("Clear All Cache", role: .destructive) { vm.clearAll(videos) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(vm.isClearing)
                }
            }
        }
        .fullScreenCover(item: $playingURL) { item in
            PlayerSheet(url: item.url)
        }
        .onAppear {
            vm.checkAll(videos)
            Task { await vm.refreshDiskSize() }
        }
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

            if let p = status.downloadProgress {
                ProgressView(value: p)
                    .tint(.orange)
                    .animation(.linear(duration: 0.1), value: p)
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
                    EmptyView()

                case .cached(_, _, let source):
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
                    .tint(status.color)

                    Image(systemName: source.icon)
                        .foregroundStyle(status.color)
                        .font(.caption)

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
