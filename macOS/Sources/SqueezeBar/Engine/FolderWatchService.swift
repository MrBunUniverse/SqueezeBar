import Foundation
import Combine

public final class FolderWatchService: @unchecked Sendable {
    public static let shared = FolderWatchService()
    
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.squeezebar.folderwatch.queue", qos: .utility)
    private var knownFiles: Set<String> = []
    private var debounceTimer: Task<Void, Never>?
    
    private init() {}
    
    public func startMonitoring(path: String) {
        queue.async { [self] in
            stopMonitoringOnQueue()

            let fileManager = FileManager.default
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                return
            }

            // Populate existing files so we only process new arrivals
            if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
                knownFiles = Set(contents)
            }

            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return }
            fileDescriptor = fd

            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link],
                queue: queue
            )

            src.setEventHandler { [weak self] in
                self?.handleFolderEvent(path: path)
            }

            src.setCancelHandler { [weak self] in
                close(fd)
                if self?.fileDescriptor == fd {
                    self?.fileDescriptor = -1
                }
            }

            source = src
            src.resume()
        }
    }
    
    public func stopMonitoring() {
        queue.async { [self] in
            stopMonitoringOnQueue()
        }
    }

    private func stopMonitoringOnQueue() {
        debounceTimer?.cancel()
        debounceTimer = nil
        source?.cancel()
        source = nil
        knownFiles.removeAll()
    }
    
    private func handleFolderEvent(path: String) {
        debounceTimer?.cancel()
        debounceTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 sec debounce for file write completion
            guard let self, !Task.isCancelled else { return }
            
            let fileManager = FileManager.default
            guard let currentContents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
            
            let currentSet = Set(currentContents)
            let newItems = self.queue.sync { currentSet.subtracting(self.knownFiles) }
            guard !newItems.isEmpty, !Task.isCancelled else { return }
            
            let config = await AppState.shared.currentConfiguration()
            let suffix = config.suffix.isEmpty ? "_min" : config.suffix
            
            var candidates: [(name: String, url: URL)] = []
            var skippedNames: [String] = []
            for item in newItems {
                if Self.shouldSkip(fileName: item, suffix: suffix) {
                    skippedNames.append(item)
                    continue
                }
                
                let itemURL = URL(fileURLWithPath: path).appendingPathComponent(item)
                if MediaType.classify(url: itemURL) != .unsupported {
                    candidates.append((item, itemURL))
                } else {
                    skippedNames.append(item)
                }
            }
            
            if !skippedNames.isEmpty {
                self.queue.sync { self.knownFiles.formUnion(skippedNames) }
            }

            await self.pollAndProcess(candidates)
        }
    }

    static func shouldSkip(fileName: String, suffix: String) -> Bool {
        if fileName.hasPrefix(".") || fileName.hasPrefix("clipboard_") {
            return true
        }
        guard !suffix.isEmpty else { return false }
        let baseName = (fileName as NSString).deletingPathExtension
        return baseName.hasSuffix(suffix)
    }

    /// Polls all candidates together until each file's size stops changing, handing off stable batches each second. Gives up after ~2 minutes.
    private func pollAndProcess(_ candidates: [(name: String, url: URL)]) async {
        var pending = candidates
        var lastSizes: [URL: Int64] = [:]
        let fm = FileManager.default

        for _ in 0..<120 {
            guard !pending.isEmpty, !Task.isCancelled else { return }

            var stableURLs: [URL] = []
            var stableNames: [String] = []
            var stillPending: [(name: String, url: URL)] = []

            for entry in pending {
                guard let size = (try? fm.attributesOfItem(atPath: entry.url.path))?[.size] as? Int64 else {
                    continue
                }
                if lastSizes[entry.url] == size {
                    stableURLs.append(entry.url)
                    stableNames.append(entry.name)
                    lastSizes.removeValue(forKey: entry.url)
                } else {
                    lastSizes[entry.url] = size
                    stillPending.append(entry)
                }
            }

            if !stableURLs.isEmpty, !Task.isCancelled {
                queue.sync { knownFiles.formUnion(stableNames) }
                // Don't await: keep polling the rest while this batch compresses.
                Task { await MediaCompressionEngine.shared.processDroppedURLs(stableURLs) }
            }

            pending = stillPending
            guard !pending.isEmpty, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
