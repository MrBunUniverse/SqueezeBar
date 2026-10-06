import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import CoreMedia
import PDFKit

public actor MediaCompressionEngine {
    public static let shared = MediaCompressionEngine()
    
    private let imageCompressor = AcceleratedImageCompressor()
    private let videoCompressor = HardwareVideoCompressor()
    private let audioCompressor = HardwareAudioCompressor()
    private let pdfCompressor = AcceleratedPDFCompressor()
    
    private var activeJobTasks: [UUID: Task<Void, Never>] = [:]
    private var activeDestinationURLs: [UUID: URL] = [:]
    private var cancelledJobIds: Set<UUID> = []
    
    private init() {}
    
    // MARK: - Cancellation API
    public func cancelJob(id: UUID) {
        cancelledJobIds.insert(id)
        if let destURL = activeDestinationURLs[id] {
            try? FileManager.default.removeItem(at: destURL)
            activeDestinationURLs.removeValue(forKey: id)
        }
        if let task = activeJobTasks[id] {
            task.cancel()
            activeJobTasks.removeValue(forKey: id)
        }
    }
    
    public func cancelAllJobs() {
        for (id, task) in activeJobTasks {
            cancelledJobIds.insert(id)
            task.cancel()
            if let destURL = activeDestinationURLs[id] {
                try? FileManager.default.removeItem(at: destURL)
            }
        }
        activeJobTasks.removeAll()
        activeDestinationURLs.removeAll()
    }
    
    private func isCancelled(_ jobId: UUID) -> Bool {
        cancelledJobIds.contains(jobId) || Task.isCancelled || JobControlRegistry.shared.control(for: jobId).isCancelled
    }
    
    private func registerJobTask(id: UUID, task: Task<Void, Never>) {
        activeJobTasks[id] = task
    }
    
    private func unregisterJobTask(id: UUID) {
        activeJobTasks.removeValue(forKey: id)
        activeDestinationURLs.removeValue(forKey: id)
    }
    
    // MARK: - Staged Queue Processing Entry Point (Per-File Custom Configurations)
    public func processStagedItems(_ items: [StagedQueueItem], targetFolderId: UUID? = nil) async {
        guard !items.isEmpty else { return }
        
        let baseConfig = await AppState.shared.currentConfiguration()
        var jobsToRun: [(url: URL, type: MediaType, jobId: UUID, origSize: Int64, config: CompressionConfiguration)] = []
        
        for item in items {
            let mediaType = item.mediaType
            guard mediaType != .unsupported else { continue }
            
            let originalSize = item.originalSize > 0 ? item.originalSize : fileSize(of: item.fileURL)
            let jobId = UUID()
            let itemConfig = item.buildConfiguration(baseConfig: baseConfig)
            
            let job = CompressionJob(
                id: jobId,
                fileURL: item.fileURL,
                mediaType: mediaType,
                progress: 0.0,
                statusText: String(localized: "Queued")
            )
            
            _ = JobControlRegistry.shared.control(for: jobId)
            await AppState.shared.addJob(job)
            jobsToRun.append((url: item.fileURL, type: mediaType, jobId: jobId, origSize: originalSize, config: itemConfig))
        }
        
        guard !jobsToRun.isEmpty else { return }
        
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent: Int = max(2, min(cores <= 8 ? 2 : 4, jobsToRun.count))
        
        var anySucceeded = false
        await withTaskGroup(of: Bool.self) { group in
            var running = 0
            for item in jobsToRun {
                if running >= maxConcurrent {
                    if let res = await group.next(), res { anySucceeded = true }
                    running -= 1
                }
                
                running += 1
                group.addTask {
                    let task = Task {
                        await self.processSingleFile(
                            url: item.url,
                            mediaType: item.type,
                            jobId: item.jobId,
                            originalSize: item.origSize,
                            config: item.config,
                            targetFolderId: targetFolderId
                        )
                    }
                    await self.registerJobTask(id: item.jobId, task: task)
                    await task.value
                    await self.unregisterJobTask(id: item.jobId)
                    return true
                }
            }
            
            for await res in group {
                if res { anySucceeded = true }
            }
        }
        
        if anySucceeded {
            await AppState.shared.triggerSuccessBadge()
        }
    }
    
    // MARK: - Batch Processing Entry Point
    public func processDroppedURLs(_ urls: [URL], targetFolderId: UUID? = nil) async {
        // 1. Gather all individual media files (recursively expanding folders)
        let resolvedFiles = gatherMediaFiles(from: urls)
        guard !resolvedFiles.isEmpty else { return }
        
        // 2. Fetch current config from main actor
        let config = await AppState.shared.currentConfiguration()
        
        // 3. Register jobs in AppState
        var jobsToRun: [(url: URL, type: MediaType, jobId: UUID, origSize: Int64)] = []
        for url in resolvedFiles {
            let mediaType = MediaType.classify(url: url)
            guard mediaType != .unsupported else { continue }
            
            let originalSize = fileSize(of: url)
            let jobId = UUID()
            let job = CompressionJob(
                id: jobId,
                fileURL: url,
                mediaType: mediaType,
                progress: 0.0,
                statusText: String(localized: "Queued")
            )
            
            _ = JobControlRegistry.shared.control(for: jobId)
            await AppState.shared.addJob(job)
            jobsToRun.append((url: url, type: mediaType, jobId: jobId, origSize: originalSize))
        }
        
        guard !jobsToRun.isEmpty else { return }
        
        // 4. Adaptive hardware concurrency tuned for Apple Silicon Media Engines:
        // - 8GB M1/M2: 2 concurrent heavy transcode tasks to prevent memory paging & keep unified memory cool
        // - 16GB+ M1/M2/M3/M4 Pro/Max: 3-4 concurrent streams for maximum hardware encoder throughput
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent: Int = max(2, min(cores <= 8 ? 2 : 4, jobsToRun.count))
        
        var anySucceeded = false
        await withTaskGroup(of: Bool.self) { group in
            var running = 0
            for item in jobsToRun {
                if running >= maxConcurrent {
                    if let res = await group.next(), res { anySucceeded = true }
                    running -= 1
                }
                
                running += 1
                group.addTask {
                    let task = Task {
                        await self.processSingleFile(
                            url: item.url,
                            mediaType: item.type,
                            jobId: item.jobId,
                            originalSize: item.origSize,
                            config: config,
                            targetFolderId: targetFolderId
                        )
                    }
                    await self.registerJobTask(id: item.jobId, task: task)
                    await task.value
                    await self.unregisterJobTask(id: item.jobId)
                    return true
                }
            }
            
            for await res in group {
                if res { anySucceeded = true }
            }
        }
        
        // 5. Trigger success feedback on UI if jobs finished without total cancellation
        if anySucceeded {
            await AppState.shared.triggerSuccessBadge()
        }
    }
    
    // MARK: - Single File Processing
    private func processSingleFile(
        url: URL,
        mediaType: MediaType,
        jobId: UUID,
        originalSize: Int64,
        config: CompressionConfiguration,
        targetFolderId: UUID? = nil
    ) async {
        if isCancelled(jobId) {
            cancelledJobIds.remove(jobId)
            await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
            return
        }
        
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let origDim = await probeDimensions(for: url, mediaType: mediaType)
        let startTime = Date()
        var destinationURL = generateDestinationURL(for: url, mediaType: mediaType, config: config)
        activeDestinationURLs[jobId] = destinationURL
        
        await AppState.shared.updateJob(id: jobId, progress: 0.05, statusText: String(localized: "Compressing..."))
        
        do {
            if isCancelled(jobId) {
                throw NSError(domain: "SqueezeBar", code: -999, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])
            }
            try await executeCompression(
                sourceURL: url,
                destinationURL: destinationURL,
                mediaType: mediaType,
                config: config,
                jobId: jobId
            )
        } catch {
            if isCancelled(jobId) {
                cancelledJobIds.remove(jobId)
                try? FileManager.default.removeItem(at: destinationURL)
                await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
                return
            }
            
            // Permission or write error fallback: attempt writing to ~/Downloads
            let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let fallbackURL = generateDestinationURL(for: url, inFolder: downloadsFolder, mediaType: mediaType, config: config)
            
            do {
                destinationURL = fallbackURL
                activeDestinationURLs[jobId] = destinationURL
                
                if isCancelled(jobId) {
                    throw NSError(domain: "SqueezeBar", code: -999, userInfo: [NSLocalizedDescriptionKey: "Cancelled"])
                }
                try await executeCompression(
                    sourceURL: url,
                    destinationURL: destinationURL,
                    mediaType: mediaType,
                    config: config,
                    jobId: jobId
                )
            } catch {
                if isCancelled(jobId) {
                    cancelledJobIds.remove(jobId)
                    try? FileManager.default.removeItem(at: destinationURL)
                    await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
                    return
                }
                await AppState.shared.finishJob(id: jobId, result: nil, error: error.localizedDescription)
                return
            }
        }
        
        if isCancelled(jobId) {
            cancelledJobIds.remove(jobId)
            try? FileManager.default.removeItem(at: destinationURL)
            await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
            return
        }
        
        let compressedSize = fileSize(of: destinationURL)
        let duration = Date().timeIntervalSince(startTime)
        let outDim = await probeDimensions(for: destinationURL, mediaType: mediaType)
        
        let result = CompressionResult(
            originalURL: url,
            outputURL: destinationURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            duration: duration,
            mediaType: mediaType,
            originalDimensions: origDim,
            outputDimensions: outDim,
            folderId: targetFolderId
        )
        
        await AppState.shared.finishJob(id: jobId, result: result, error: nil)
    }
    
    private func executeCompression(
        sourceURL: URL,
        destinationURL: URL,
        mediaType: MediaType,
        config: CompressionConfiguration,
        jobId: UUID
    ) async throws {
        let gate = ProgressGate()
        let control = JobControlRegistry.shared.control(for: jobId)
        switch mediaType {
        case .image:
            try imageCompressor.compressImage(
                from: sourceURL,
                to: destinationURL,
                config: config,
                control: control
            ) { progress in
                guard gate.shouldReport(progress) else { return }
                Task { @MainActor in
                    AppState.shared.updateJob(id: jobId, progress: progress, statusText: String(localized: "Compressing \(Int(progress * 100))%"))
                }
            }
            
        case .video:
            try await videoCompressor.compressVideo(
                from: sourceURL,
                to: destinationURL,
                config: config,
                control: control
            ) { progress in
                guard gate.shouldReport(progress) else { return }
                Task { @MainActor in
                    AppState.shared.updateJob(id: jobId, progress: progress, statusText: String(localized: "Encoding \(Int(progress * 100))%"))
                }
            }
            
        case .audio:
            try await audioCompressor.compressAudio(
                from: sourceURL,
                to: destinationURL,
                config: config,
                control: control
            ) { progress in
                guard gate.shouldReport(progress) else { return }
                Task { @MainActor in
                    AppState.shared.updateJob(id: jobId, progress: progress, statusText: String(localized: "Encoding \(Int(progress * 100))%"))
                }
            }
            
        case .pdf:
            try pdfCompressor.compressPDF(
                from: sourceURL,
                to: destinationURL,
                config: config,
                control: control
            ) { progress in
                guard gate.shouldReport(progress) else { return }
                Task { @MainActor in
                    AppState.shared.updateJob(id: jobId, progress: progress, statusText: String(localized: "Optimizing PDF \(Int(progress * 100))%"))
                }
            }
            
        case .unsupported:
            throw NSError(domain: "SqueezeBar", code: 400, userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported media format")])
        }
    }
    
    // MARK: - Destination Path Generation
    private func generateDestinationURL(
        for sourceURL: URL,
        inFolder customFolder: URL? = nil,
        mediaType: MediaType,
        config: CompressionConfiguration
    ) -> URL {
        var folder = customFolder ?? sourceURL.deletingLastPathComponent()
        if customFolder == nil, let customPath = config.customOutputFolder, !customPath.isEmpty {
            let customDir = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: customDir.path) {
                folder = customDir
            }
        }
        
        // Auto-create subfolder (e.g. "Squeezed") if enabled
        if customFolder == nil && config.exportToSubfolder {
            let subfolderName = config.subfolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Squeezed" : config.subfolderName
            let targetSubfolder = folder.appendingPathComponent(subfolderName)
            if !FileManager.default.fileExists(atPath: targetSubfolder.path) {
                try? FileManager.default.createDirectory(at: targetSubfolder, withIntermediateDirectories: true)
            }
            folder = targetSubfolder
        }
        
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        
        let targetExt: String
        switch mediaType {
        case .image:
            targetExt = imageCompressor.outputExtension(for: sourceURL, config: config)
        case .video:
            targetExt = videoCompressor.outputExtension(for: sourceURL, config: config)
        case .audio:
            targetExt = audioCompressor.outputExtension(for: sourceURL, config: config)
        case .pdf:
            targetExt = pdfCompressor.outputExtension(for: sourceURL, config: config)
        case .unsupported:
            targetExt = sourceURL.pathExtension
        }
        
        let suffix = config.suffix.isEmpty ? "_min" : config.suffix
        var candidateName = "\(baseName)\(suffix).\(targetExt)"
        var candidateURL = folder.appendingPathComponent(candidateName)
        
        // Avoid overwriting if candidate already exists
        var counter = 1
        while FileManager.default.fileExists(atPath: candidateURL.path) && candidateURL.path != sourceURL.path {
            candidateName = "\(baseName)\(suffix) (\(counter)).\(targetExt)"
            candidateURL = folder.appendingPathComponent(candidateName)
            counter += 1
        }
        
        return candidateURL
    }
    
    // MARK: - Modern Async Dimension & Format Probing (Zero Main Thread Stalls)
    private func probeDimensions(for url: URL, mediaType: MediaType) async -> String? {
        switch mediaType {
        case .image:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
            if let w = props[kCGImagePropertyPixelWidth] as? Int,
               let h = props[kCGImagePropertyPixelHeight] as? Int {
                return "\(w) × \(h)"
            }
            return nil
        case .video:
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
                var infoParts: [String] = []
                
                // 1. Resolution
                if let size = try? await track.load(.naturalSize),
                   let transform = try? await track.load(.preferredTransform) {
                    let oriented = size.applying(transform)
                    let w = Int(abs(oriented.width))
                    let h = Int(abs(oriented.height))
                    infoParts.append("\(w) × \(h)")
                }
                
                // 2. Framerate (FPS)
                if let nominalFPS = try? await track.load(.nominalFrameRate), nominalFPS > 0 {
                    let roundedFPS: String
                    if abs(nominalFPS - round(nominalFPS)) < 0.05 {
                        roundedFPS = String(format: "%.0f fps", nominalFPS)
                    } else {
                        roundedFPS = String(format: "%.2f fps", nominalFPS)
                    }
                    infoParts.append(roundedFPS)
                }
                
                // 3. Bitrate (Mbps / kbps)
                var bitrateBps: Double = 0
                if let estRate = try? await track.load(.estimatedDataRate), estRate > 0 {
                    bitrateBps = Double(estRate)
                } else if let duration = try? await asset.load(.duration) {
                    let durSec = CMTimeGetSeconds(duration)
                    if durSec > 0, let fileAttrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let fileSize = fileAttrs[.size] as? Int64 {
                        bitrateBps = (Double(fileSize) * 8.0) / durSec
                    }
                }
                
                if bitrateBps > 0 {
                    if bitrateBps >= 1_000_000 {
                        infoParts.append(String(format: "%.1f Mbps", bitrateBps / 1_000_000.0))
                    } else {
                        infoParts.append(String(format: "%.0f kbps", bitrateBps / 1_000.0))
                    }
                }
                
                return infoParts.isEmpty ? nil : infoParts.joined(separator: " • ")
            }
            return nil
        case .audio:
            let asset = AVURLAsset(url: url)
            if let duration = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(duration)
                if sec > 0 {
                    let m = Int(sec) / 60
                    let s = Int(sec) % 60
                    return String(format: "%d:%02d", m, s)
                }
            }
            return nil
        case .pdf:
            if let doc = PDFDocument(url: url), doc.pageCount > 0 {
                let count = doc.pageCount
                if let firstPage = doc.page(at: 0) {
                    let b = firstPage.bounds(for: .mediaBox)
                    let w = Int(b.width)
                    let h = Int(b.height)
                    return "\(count) \(count == 1 ? "Page" : "Pages") • \(w) × \(h) pt"
                }
                return "\(count) \(count == 1 ? "Page" : "Pages")"
            }
            return nil
        case .unsupported:
            return nil
        }
    }
    
    // MARK: - File & Directory Traversal (Batch Folder Support)
    nonisolated public func gatherMediaFiles(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fileManager = FileManager.default
        
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Recursive directory enumerator for folders
                    if let enumerator = fileManager.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        for case let fileURL as URL in enumerator {
                            if MediaType.classify(url: fileURL) != .unsupported {
                                result.append(fileURL)
                            }
                        }
                    }
                } else {
                    if MediaType.classify(url: url) != .unsupported {
                        result.append(url)
                    }
                }
            }
        }
        
        var seen = Set<String>()
        return result.filter { seen.insert($0.path).inserted }
    }
    
    private func fileSize(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }
}


/// Encoders report progress per frame; only forward whole-percent changes so the UI isn't invalidated hundreds of times a second.
private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1

    func shouldReport(_ progress: Double) -> Bool {
        let percent = Int(progress * 100)
        lock.lock()
        defer { lock.unlock() }
        guard percent != lastPercent else { return false }
        lastPercent = percent
        return true
    }
}
