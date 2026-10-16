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
        stopMonitoring()
        
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        
        // Populate existing files so we only process new arrivals
        if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
            knownFiles = Set(contents)
        }
        
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .link],
            queue: queue
        )
        
        src.setEventHandler { [weak self] in
            self?.handleFolderEvent(path: path)
        }
        
        src.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        
        self.source = src
        src.resume()
    }
    
    public func stopMonitoring() {
        source?.cancel()
        source = nil
        knownFiles.removeAll()
    }
    
    private func handleFolderEvent(path: String) {
        debounceTimer?.cancel()
        debounceTimer = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 sec debounce for file write completion
            guard !Task.isCancelled else { return }
            
            let fileManager = FileManager.default
            guard let currentContents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
            
            let currentSet = Set(currentContents)
            let newItems = currentSet.subtracting(self.knownFiles)
            self.knownFiles = currentSet
            
            let config = await AppState.shared.currentConfiguration()
            let suffix = MediaCompressionEngine.outputSuffix(config.suffix)
            
            var candidates: [URL] = []
            for item in newItems {
                if item.hasPrefix(".") || item.contains(suffix) || item.hasPrefix("clipboard_") {
                    continue
                }
                
                let itemURL = URL(fileURLWithPath: path).appendingPathComponent(item)
                if MediaType.classify(url: itemURL) != .unsupported {
                    candidates.append(itemURL)
                }
            }
            
            // Skip files still being copied in; one wait covers the whole batch.
            let urlsToProcess = await Self.waitUntilStable(candidates)
            if !urlsToProcess.isEmpty, !Task.isCancelled {
                await MediaCompressionEngine.shared.processDroppedURLs(urlsToProcess)
            }
        }
    }

    /// Polls all files together until their sizes stop changing (copy finished). Returns the stable ones; gives up after ~2 minutes.
    private static func waitUntilStable(_ urls: [URL]) async -> [URL] {
        var pending = urls
        var lastSizes: [URL: Int64] = [:]
        var ready: [URL] = []
        for _ in 0..<120 {
            guard !Task.isCancelled, !pending.isEmpty else { break }
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
