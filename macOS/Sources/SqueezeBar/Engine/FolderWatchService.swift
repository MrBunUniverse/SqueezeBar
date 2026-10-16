import Foundation

/// Auto-squeeze watch folder. All mutable state lives on `queue`; start and stop may be called from any thread.
public final class FolderWatchService: @unchecked Sendable {
    public static let shared = FolderWatchService()

    private let queue = DispatchQueue(label: "com.squeezebar.folderwatch.queue", qos: .utility)
    // Everything below is only touched on `queue`.
    private var source: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var knownFiles: Set<String> = []
    /// Bumped on every start and stop, so batches still waiting for a copy to finish are dropped once watching changes.
    private var generation = 0

    private init() {}

    public func startMonitoring(path: String) {
        queue.sync {
            stopLocked()
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }

            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return }
            // Existing files are left alone; only new arrivals are squeezed.
            knownFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
            watchedPath = path

            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link],
                queue: queue
            )
            let generation = generation
            src.setEventHandler { [weak self] in
                self?.handleFolderEvent(path: path, generation: generation)
            }
            // Close this source's own descriptor: by the time the handler runs, a newer source may be watching.
            src.setCancelHandler { close(fd) }
            source = src
            src.resume()
        }
    }

    public func stopMonitoring() {
        queue.sync { stopLocked() }
    }

    private func stopLocked() {
        source?.cancel()
        source = nil
        watchedPath = nil
        knownFiles.removeAll()
        generation += 1
    }

    /// Runs on `queue`. Each event hands its new files to their own batch, which later events never cancel,
    /// so nothing is lost when files keep arriving while an earlier copy is still in progress.
    private func handleFolderEvent(path: String, generation: Int) {
        guard generation == self.generation, path == watchedPath,
              let currentContents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }

        let currentSet = Set(currentContents)
        let newItems = currentSet.subtracting(knownFiles)
        knownFiles = currentSet
        guard !newItems.isEmpty else { return }

        Task {
            let config = await AppState.shared.currentConfiguration()
            let suffix = MediaCompressionEngine.outputSuffix(config.suffix)
            let candidates = newItems
                .filter { !$0.hasPrefix(".") && !$0.contains(suffix) && !$0.hasPrefix("clipboard_") }
                .map { URL(fileURLWithPath: path).appendingPathComponent($0) }
                .filter { MediaType.classify(url: $0) != .unsupported }
            guard !candidates.isEmpty else { return }

            // Skip files still being copied in; one wait covers the whole batch.
            let urlsToProcess = await Self.waitUntilStable(candidates)
            guard !urlsToProcess.isEmpty, self.isCurrent(generation) else { return }
            await MediaCompressionEngine.shared.processDroppedURLs(urlsToProcess)
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        queue.sync { generation == self.generation }
    }

    /// Polls all files together until their sizes stop changing (copy finished). Returns the stable ones; gives up after ~2 minutes.
    private static func waitUntilStable(_ urls: [URL]) async -> [URL] {
        var pending = urls
        var lastSizes: [URL: Int64] = [:]
        var ready: [URL] = []
        for _ in 0..<120 {
            guard !pending.isEmpty else { break }
            var stillChanging: [URL] = []
            for url in pending {
                // A file that vanished is dropped; one still growing waits for the next sample.
                guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else { continue }
                if lastSizes[url] == size {
                    ready.append(url)
                } else {
                    lastSizes[url] = size
                    stillChanging.append(url)
                }
            }
            pending = stillChanging
            if pending.isEmpty { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return ready
    }
}
