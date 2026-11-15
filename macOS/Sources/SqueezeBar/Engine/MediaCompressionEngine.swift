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
    
    private var activeJobTasks: [UUID: Task<Bool, Never>] = [:]
    private var activeDestinationURLs: [UUID: URL] = [:]
    private var cancelledJobIds: Set<UUID> = []
    private var runningJobCount = 0
    
    // App-wide cap shared by every entry path (2 jobs on <=8 cores, else 4).
    private static let maxConcurrentJobs = ProcessInfo.processInfo.activeProcessorCount <= 8 ? 2 : 4
    private var activeSlots = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    
    private init() {}
    
    private func acquireSlot() async {
        if activeSlots < Self.maxConcurrentJobs {
            activeSlots += 1
            return
        }
        await withCheckedContinuation { slotWaiters.append($0) }
    }
    
    private func releaseSlot() {
        if slotWaiters.isEmpty {
            activeSlots -= 1
        } else {
            slotWaiters.removeFirst().resume() // hand the slot straight to the next waiter
        }
    }
    
    /// Returns once no job is running. A cancelled job deletes its partial output as it stops,
    /// so quitting waits here instead of exiting mid-cleanup.
    public func waitUntilIdle() async {
        while runningJobCount > 0 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    
    // MARK: - Cancellation API
    public func cancelJob(id: UUID) {
        guard activeJobTasks[id] != nil || activeDestinationURLs[id] != nil else { return }
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
    
    private func registerJobTask(id: UUID, task: Task<Bool, Never>) {
        activeJobTasks[id] = task
    }
    
    private func unregisterJobTask(id: UUID) {
        activeJobTasks.removeValue(forKey: id)
        activeDestinationURLs.removeValue(forKey: id)
        cancelledJobIds.remove(id)
    }
    
    /// Pure helper: true when the compressed output saved bytes vs. the source.
    nonisolated public static func didSaveBytes(originalSize: Int64, compressedSize: Int64) -> Bool {
        originalSize > 0 && compressedSize > 0 && compressedSize < originalSize
    }
    
    /// A job that has its row in AppState and is ready to run.
    private struct PendingJob {
        let url: URL
        let mediaType: MediaType
        let jobId: UUID
        let originalSize: Int64
        let config: CompressionConfiguration
    }
    
    // MARK: - Staged Queue Processing Entry Point (Per-File Custom Configurations)
    public func processStagedItems(_ items: [StagedQueueItem], targetFolderId: UUID? = nil) async {
        let baseConfig = await AppState.shared.currentConfiguration()
        var jobs: [PendingJob] = []
        for item in items {
            let mediaType = item.mediaType
            guard mediaType != .unsupported else { continue }
            
            let originalSize = item.originalSize > 0 ? item.originalSize : fileSize(of: item.fileURL)
            let itemConfig = item.buildConfiguration(baseConfig: baseConfig)
            let pending = await registerJob(url: item.fileURL, mediaType: mediaType, originalSize: originalSize, config: itemConfig)
            jobs.append(pending)
        }
        
        await runJobs(jobs, targetFolderId: targetFolderId, droppedURLs: items.map(\.fileURL))
    }
    
    // MARK: - Batch Processing Entry Point
    public func processDroppedURLs(_ urls: [URL], targetFolderId: UUID? = nil) async {
        // 1. Gather all individual media files (recursively expanding folders)
        let resolvedFiles = gatherMediaFiles(from: urls)
        guard !resolvedFiles.isEmpty else {
            await AppState.shared.reportNoSupportedFiles(urls: urls)
            return
        }
        
        // 2. Fetch current config from main actor
        let config = await AppState.shared.currentConfiguration()
        
        // 3. Register jobs in AppState
        var jobs: [PendingJob] = []
        for url in resolvedFiles {
            let mediaType = MediaType.classify(url: url)
            guard mediaType != .unsupported else { continue }
            
            let pending = await registerJob(url: url, mediaType: mediaType, originalSize: fileSize(of: url), config: config)
            jobs.append(pending)
        }
        
        await runJobs(jobs, targetFolderId: targetFolderId, droppedURLs: urls)
    }
    
    private func registerJob(url: URL, mediaType: MediaType, originalSize: Int64, config: CompressionConfiguration) async -> PendingJob {
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
        return PendingJob(url: url, mediaType: mediaType, jobId: jobId, originalSize: originalSize, config: config)
    }
    
    private func runJobs(_ jobs: [PendingJob], targetFolderId: UUID?, droppedURLs: [URL]) async {
        guard !jobs.isEmpty else {
            await AppState.shared.reportNoSupportedFiles(urls: droppedURLs)
            return
        }
        
        // Concurrency is capped app-wide in processSingleFile (acquireSlot), shared by every entry path.
        var anySucceeded = false
        await withTaskGroup(of: Bool.self) { group in
            for item in jobs {
                group.addTask {
                    let task = Task { () -> Bool in
                        await self.processSingleFile(
                            url: item.url,
                            mediaType: item.mediaType,
                            jobId: item.jobId,
                            originalSize: item.originalSize,
                            config: item.config,
                            targetFolderId: targetFolderId
                        )
                    }
                    await self.registerJobTask(id: item.jobId, task: task)
                    let succeeded = await task.value
                    await self.unregisterJobTask(id: item.jobId)
                    return succeeded
                }
            }
            
            for await res in group {
                if res { anySucceeded = true }
            }
        }
        
        // Trigger success feedback on UI only if at least one job actually saved bytes
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
    ) async -> Bool {
        await acquireSlot()
        runningJobCount += 1
        defer {
            runningJobCount -= 1
            releaseSlot()
        }
        
        if isCancelled(jobId) {
            cancelledJobIds.remove(jobId)
            await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
            return false
        }
        
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Videos are probed and encoded from one asset, so the source's tracks are parsed once.
        let sourceAsset = mediaType == .video ? AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]) : nil
        let origDim = await probeDimensions(for: url, mediaType: mediaType, preloadedAsset: sourceAsset)
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
                sourceAsset: sourceAsset,
                jobId: jobId
            )
        } catch {
            if isCancelled(jobId) {
                cancelledJobIds.remove(jobId)
                try? FileManager.default.removeItem(at: destinationURL)
                await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
                return false
            }
            
            // Fall back to ~/Downloads only when the destination folder can't be written;
            // other failures (corrupt/unsupported input) would just fail again after a second full encode.
            guard !FileManager.default.isWritableFile(atPath: destinationURL.deletingLastPathComponent().path) else {
                try? FileManager.default.removeItem(at: destinationURL)
                await AppState.shared.finishJob(id: jobId, result: nil, error: error.localizedDescription)
                return false
            }
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
                    sourceAsset: sourceAsset,
                    jobId: jobId
                )
            } catch {
                if isCancelled(jobId) {
                    cancelledJobIds.remove(jobId)
                    try? FileManager.default.removeItem(at: destinationURL)
                    await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
                    return false
                }
                await AppState.shared.finishJob(id: jobId, result: nil, error: error.localizedDescription)
                return false
            }
        }
        
        if isCancelled(jobId) {
            cancelledJobIds.remove(jobId)
            try? FileManager.default.removeItem(at: destinationURL)
            await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
            return false
        }
        
        let compressedSize = fileSize(of: destinationURL)
        let duration = Date().timeIntervalSince(startTime)
        if !Self.didSaveBytes(originalSize: originalSize, compressedSize: compressedSize) {
            try? FileManager.default.removeItem(at: destinationURL)
            await AppState.shared.finishJob(id: jobId, result: nil, error: nil, statusOverride: String(localized: "Already optimized"))
            return false
        }
        
        let outDim = await probeDimensions(for: destinationURL, mediaType: mediaType)
        if isCancelled(jobId) {
            cancelledJobIds.remove(jobId)
            try? FileManager.default.removeItem(at: destinationURL)
            await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
            return false
        }
        
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
        return true
    }
    
    private func executeCompression(
        sourceURL: URL,
        destinationURL: URL,
        mediaType: MediaType,
        config: CompressionConfiguration,
        sourceAsset: AVURLAsset?,
        jobId: UUID
    ) async throws {
        let gate = ProgressGate()
        let control = JobControlRegistry.shared.control(for: jobId)
        switch mediaType {
        case .image:
            // Run off the engine actor so images/PDFs encode in parallel and the actor stays responsive.
            let imageCompressor = self.imageCompressor
            try await Task.detached(priority: .userInitiated) {
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
            }.value
            
        case .video:
            try await videoCompressor.compressVideo(
                from: sourceURL,
                to: destinationURL,
                config: config,
                control: control,
                preloadedAsset: sourceAsset
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
            let pdfCompressor = self.pdfCompressor
            try await Task.detached(priority: .userInitiated) {
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
            }.value
            
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
        let isClipboardTemp = sourceURL.lastPathComponent.hasPrefix("clipboard_")
            && sourceURL.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL
        var folder = customFolder ?? sourceURL.deletingLastPathComponent()
        if !isClipboardTemp, customFolder == nil, let customPath = config.customOutputFolder, !customPath.isEmpty {
            let customDir = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: customDir.path) {
                folder = customDir
            }
        }
        
        // Auto-create subfolder (e.g. "Squeezed") if enabled
        if !isClipboardTemp && customFolder == nil && config.exportToSubfolder {
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
        let reservedPaths = Set(activeDestinationURLs.values.map(\.path))
        return Self.uniqueDestinationURL(
            folder: folder,
            baseName: baseName,
            suffix: suffix,
            extension: targetExt,
            sourceURL: sourceURL,
            reservedPaths: reservedPaths
        )
    }

    /// Picks an output name that never collides with an existing file, the source itself,
    /// or a path reserved by another running job.
    static func uniqueDestinationURL(
        folder: URL,
        baseName: String,
        suffix: String,
        extension targetExt: String,
        sourceURL: URL,
        reservedPaths: Set<String> = []
    ) -> URL {
        let fm = FileManager.default
        let sourcePath = sourceURL.standardizedFileURL.path
        func isTaken(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.path)
                || reservedPaths.contains(url.path)
                || url.standardizedFileURL.path == sourcePath
        }
        var candidateURL = folder.appendingPathComponent("\(baseName)\(suffix).\(targetExt)")
        var counter = 1
        while isTaken(candidateURL) {
            candidateURL = folder.appendingPathComponent("\(baseName)\(suffix) (\(counter)).\(targetExt)")
            counter += 1
        }
        return candidateURL
    }
    
    // MARK: - Modern Async Dimension & Format Probing (Zero Main Thread Stalls)
    private func probeDimensions(for url: URL, mediaType: MediaType, preloadedAsset: AVURLAsset? = nil) async -> String? {
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
            let asset = preloadedAsset ?? AVURLAsset(url: url)
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
                    let fpsUnit = String(localized: "fps")
                    let roundedFPS: String
                    if abs(nominalFPS - round(nominalFPS)) < 0.05 {
                        roundedFPS = String(format: "%.0f %@", nominalFPS, fpsUnit)
                    } else {
                        roundedFPS = String(format: "%.2f %@", nominalFPS, fpsUnit)
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
                        infoParts.append(String(format: "%.1f %@", bitrateBps / 1_000_000.0, String(localized: "Mbps")))
                    } else {
                        infoParts.append(String(format: "%.0f %@", bitrateBps / 1_000.0, String(localized: "kbps")))
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
                let pageLabel = count == 1 ? String(localized: "Page") : String(localized: "Pages")
                if let firstPage = doc.page(at: 0) {
                    let b = firstPage.bounds(for: .mediaBox)
                    let w = Int(b.width)
                    let h = Int(b.height)
                    return "\(count) \(pageLabel) • \(w) × \(h) pt"
                }
                return "\(count) \(pageLabel)"
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
