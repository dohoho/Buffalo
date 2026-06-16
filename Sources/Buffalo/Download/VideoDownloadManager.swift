import Foundation

actor VideoDownloadManager {
    private var activeTasks: [CacheKey: Task<URL, Error>] = [:]
    private var activeCount = 0
    private let maxConcurrent: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    private let downloader: any VideoDownloading
    private let diskCache: DiskCache

    init(maxConcurrent: Int = 4, downloader: any VideoDownloading, diskCache: DiskCache) {
        self.maxConcurrent = maxConcurrent
        self.downloader = downloader
        self.diskCache = diskCache
    }

    func fetch(
        key: CacheKey,
        url: URL,
        fileExtension ext: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        if let existing = activeTasks[key] {
            return try await existing.value
        }

        try await acquireSlot()

        let task = Task<URL, Error> {
            let tempURL: URL
            if let pd = downloader as? any VideoDownloadingWithProgress, let cb = progress {
                tempURL = try await pd.download(from: url, progress: cb)
            } else {
                tempURL = try await downloader.download(from: url)
            }
            return try await diskCache.store(movingFrom: tempURL, forKey: key, fileExtension: ext)
        }

        activeTasks[key] = task

        do {
            let result = try await task.value
            taskFinished(key: key)
            return result
        } catch {
            taskFinished(key: key)
            throw error
        }
    }

    func cancel(key: CacheKey) {
        activeTasks[key]?.cancel()
    }

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        let pending = waiters
        waiters.removeAll()
        for (_, waiter) in pending {
            waiter.resume(throwing: CancellationError())
        }
    }

    private func acquireSlot() async throws {
        guard activeCount < maxConcurrent else {
            let id = UUID()
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        waiters.append((id: id, continuation: continuation))
                    }
                },
                onCancel: {
                    Task { await self.cancelWaiter(id: id) }
                }
            )
            return
        }
        activeCount += 1
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let (_, continuation) = waiters.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }

    private func taskFinished(key: CacheKey) {
        activeTasks.removeValue(forKey: key)
        if waiters.isEmpty {
            activeCount -= 1
        } else {
            let (_, next) = waiters.removeFirst()
            next.resume()
        }
    }
}
