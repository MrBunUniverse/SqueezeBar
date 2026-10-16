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
    
    /// Running jobs; each task returns whether it produced an output file.
    private var activeJobTasks: [UUID: Task<Bool, Never>] = [:]
    /// Final output paths of running jobs, reserved so two jobs never pick the same name.
    private var activeDestinationURLs: [UUID: URL] = [:]
    private var cancelledJobIds: Set<UUID> = []

    /// Finish message for a file the encoder couldn't make smaller. Compared in AppState, like "Cancelled".
    public static let alreadyOptimizedMessage = String(localized: "Already optimized, original kept")

    private init() {}

    // MARK: - Cancellation API
    // Tasks stay registered until they finish: processSingleFile deletes the partial output, and waitUntilIdle relies on it.
    public func cancelJob(id: UUID) {
        cancelledJobIds.insert(id)
        activeJobTasks[id]?.cancel()
    }

    public func cancelAllJobs() {
        for (id, task) in activeJobTasks {
            cancelledJobIds.insert(id)
            task.cancel()
        }
    }

    /// Waits for running jobs to stop (and clean up after themselves), up to `timeout` seconds. Used on quit.
    public func waitUntilIdle(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !activeJobTasks.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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
        guard !items.isEmpty else { return }
        
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
        
        await runJobs(jobs, targetFolderId: targetFolderId)
    }
    
    // MARK: - Batch Processing Entry Point
    public func processDroppedURLs(_ urls: [URL], targetFolderId: UUID? = nil) async {
        // 1. Gather all individual media files (recursively expanding folders)
        let resolvedFiles = gatherMediaFiles(from: urls)
        guard !resolvedFiles.isEmpty else { return }
        
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
        
        await runJobs(jobs, targetFolderId: targetFolderId)
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
    
    private func runJobs(_ jobs: [PendingJob], targetFolderId: UUID?) async {
        guard !jobs.isEmpty else { return }
        
        // Adaptive hardware concurrency tuned for Apple Silicon Media Engines:
        // - 8GB M1/M2: 2 concurrent heavy transcode tasks to prevent memory paging & keep unified memory cool
        // - 16GB+ M1/M2/M3/M4 Pro/Max: 3-4 concurrent streams for maximum hardware encoder throughput
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent: Int = max(2, min(cores <= 8 ? 2 : 4, jobs.count))
        
        var anySucceeded = false
        await withTaskGroup(of: Bool.self) { group in
            var running = 0
            for item in jobs {
                if running >= maxConcurrent {
                    if let res = await group.next(), res { anySucceeded = true }
                    running -= 1
                }
                
                running += 1
                group.addTask {
                    let task = Task {
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
        
        // The chime is for files that were actually saved, not for failures or cancels.
        if anySucceeded {
            await AppState.shared.triggerSuccessBadge()
        }
    }
    
    // MARK: - Single File Processing
    /// Returns true when a smaller copy was saved.
    private func processSingleFile(
        url: URL,
        mediaType: MediaType,
        jobId: UUID,
        originalSize: Int64,
        config: CompressionConfiguration,
        targetFolderId: UUID? = nil
    ) async -> Bool {
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
        let destinationURL = generateDestinationURL(for: url, mediaType: mediaType, config: config)
        activeDestinationURLs[jobId] = destinationURL
        // Encoders write to a hidden file next to the output; it only gets the real name once it is complete,
        // so a failure, cancel or quit never leaves a broken file that looks like a finished one.
        let partialURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".\(destinationURL.lastPathComponent)")
        
        let savingElsewhere = destinationURL.deletingLastPathComponent() == Self.downloadsFolder
            && url.deletingLastPathComponent() != Self.downloadsFolder
        await AppState.shared.updateJob(
            id: jobId,
            progress: 0.05,
            statusText: savingElsewhere ? String(localized: "Folder is read-only, saving to Downloads...") : String(localized: "Compressing...")
        )
        
        do {
            if isCancelled(jobId) { throw CancellationError() }
            try await executeCompression(
                sourceURL: url,
                destinationURL: partialURL,
                mediaType: mediaType,
                config: config,
                sourceAsset: sourceAsset,
                jobId: jobId
            )
            if isCancelled(jobId) { throw CancellationError() }
            
            // A copy that isn't smaller is useless, unless the user asked for a different format.
            let convertedOnRequest = (mediaType == .image && config.imageFormatPolicy != .preserveOriginal)
                || (mediaType == .video && config.videoCodec == .gif)
            if originalSize > 0, fileSize(of: partialURL) >= originalSize, !convertedOnRequest {
                try? FileManager.default.removeItem(at: partialURL)
                await AppState.shared.finishJob(id: jobId, result: nil, error: Self.alreadyOptimizedMessage)
                return false
            }
            try FileManager.default.moveItem(at: partialURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            if isCancelled(jobId) {
                cancelledJobIds.remove(jobId)
                await AppState.shared.finishJob(id: jobId, result: nil, error: "Cancelled")
            } else {
                await AppState.shared.finishJob(id: jobId, result: nil, error: error.localizedDescription)
            }
            return false
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
    private static let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    
    private func generateDestinationURL(
        for sourceURL: URL,
        mediaType: MediaType,
        config: CompressionConfiguration
    ) -> URL {
        var folder = sourceURL.deletingLastPathComponent()
        if let customPath = config.customOutputFolder, !customPath.isEmpty {
            let customDir = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: customDir.path) {
                folder = customDir
            }
        }
        
        // Auto-create subfolder (e.g. "Squeezed") if enabled
        if config.exportToSubfolder {
            // Dots trimmed too, so ".." can't climb out of the folder.
            let cleaned = Self.safeNamePart(config.subfolderName).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            let targetSubfolder = folder.appendingPathComponent(cleaned.isEmpty ? "Squeezed" : cleaned)
            if !FileManager.default.fileExists(atPath: targetSubfolder.path) {
                try? FileManager.default.createDirectory(at: targetSubfolder, withIntermediateDirectories: true)
            }
            folder = targetSubfolder
        }
        
        // Read-only folder (locked volume, shared drive, no permission): save to Downloads instead.
        // Decided up front, so a real encode error is reported once rather than retried elsewhere.
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            folder = Self.downloadsFolder
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
        
        let reservedPaths = Set(activeDestinationURLs.values.map(\.path))
        return Self.uniqueDestinationURL(
            folder: folder,
            baseName: baseName,
            suffix: Self.outputSuffix(config.suffix),
            extension: targetExt,
            sourceURL: sourceURL,
            reservedPaths: reservedPaths
        )
    }

    /// Text the user typed (suffix, subfolder, rename pattern) reduced to something that can only name a file
    /// inside the chosen folder: no path separators, no ":" (Finder shows it as "/"), no control characters.
    static func safeNamePart(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            $0 != "/" && $0 != ":" && !CharacterSet.controlCharacters.contains($0)
        }))
    }

    /// The suffix as it appears in output names. The watch folder recognises its own outputs by it, so both use this.
    static func outputSuffix(_ suffix: String) -> String {
        let cleaned = safeNamePart(suffix)
        return cleaned.isEmpty ? "_min" : cleaned
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
