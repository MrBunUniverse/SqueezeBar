import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox
import ImageIO
import UniformTypeIdentifiers

public struct HardwareVideoCompressor: Sendable {
    
    public enum VideoCompressorError: LocalizedError {
        case unreadableSource
        case noVideoTrackFound
        case cannotCreateReader
        case cannotCreateWriter
        case encodingFailed(String)
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .unreadableSource: return String(localized: "Unable to open or read video source file")
            case .noVideoTrackFound: return String(localized: "No valid video track found in file")
            case .cannotCreateReader: return String(localized: "Failed to initialize AVAssetReader")
            case .cannotCreateWriter: return String(localized: "Failed to initialize AVAssetWriter")
            case .encodingFailed(let msg): return String(localized: "Video encoding failed: \(msg)")
            case .cancelled: return String(localized: "Compression cancelled")
            }
        }
    }
    
    public init() {}
    
    // ==========================================================================
    // MARK: - PUBLIC API
    // ==========================================================================
    
    /// Hardware-accelerated video compression using Apple Silicon Media Engine.
    public func compressVideo(
        from sourceURL: URL,
        to destinationURL: URL,
        config: CompressionConfiguration,
        control: JobControl? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Ensure destination does not exist
        try? FileManager.default.removeItem(at: destinationURL)
        
        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        
        // Load asset properties
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
            duration = try await asset.load(.duration)
        } catch {
            throw VideoCompressorError.unreadableSource
        }
        
        guard let videoTrack = tracks.first else {
            throw VideoCompressorError.noVideoTrackFound
        }
        
        // Animated GIF Branch
        if config.videoCodec == .gif {
            try await convertVideoToAnimatedGIF(
                asset: asset,
                duration: duration,
                videoTrack: videoTrack,
                destinationURL: destinationURL,
                config: config,
                control: control,
                progressHandler: progressHandler
            )
            return
        }
        
        let totalDurationSeconds = CMTimeGetSeconds(duration)
        guard totalDurationSeconds > 0 else {
            throw VideoCompressorError.unreadableSource
        }
        
        // Load video track properties
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let sourceFPS = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30.0
        let frameRate: Double = config.videoFramerate.targetFPS ?? sourceFPS
        
        // Track output supplies unrotated pixels; the writer transform carries their display orientation.
        let sourceWidth = Int(naturalSize.width)
        let sourceHeight = Int(naturalSize.height)
        
        // ---- Source bitrate probing ----
        let sourceBitrate: Double
        if estimatedDataRate > 0 {
            sourceBitrate = Double(estimatedDataRate)
        } else {
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
            let fileSize = (fileAttrs?[.size] as? Int64) ?? 0
            sourceBitrate = (Double(fileSize) * 8.0) / totalDurationSeconds
        }
        
        // ---- Resolution & Bitrate Calculation (Manual or Target Size Automated) ----
        let videoCodec: AVVideoCodecType = config.videoCodec.avCodecType
        let sourceLongEdge = Double(max(sourceWidth, sourceHeight))
        
        var renderWidth: Int
        var renderHeight: Int
        let targetBitrate: Int
        let targetAudioBitrate: Int
        
        if let targetMB = config.effectiveTargetSizeMB {
            // Target File Size Automated Mode (e.g. 25 MB Discord, 50 MB Nitro, 10 MB Email, 2 MB Web)
            // Leave 8% safety margin for MP4 header, moov atom, and audio/video packet overhead
            let targetBytes = targetMB * 1024.0 * 1024.0 * 0.92
            let targetTotalBits = targetBytes * 8.0
            
            // Adapt audio bitrate: for small target sizes (e.g. <= 5MB), drop to 48k/64k unless locked
            if config.videoRemoveAudio {
                targetAudioBitrate = 0
            } else if config.preserveAudioQualityInTargetMode {
                targetAudioBitrate = 128_000
            } else if targetMB <= 2.5 {
                targetAudioBitrate = 48_000 // 48 kbps AAC
            } else if targetMB <= 10.0 {
                targetAudioBitrate = 64_000 // 64 kbps AAC
            } else {
                targetAudioBitrate = 96_000 // 96 kbps AAC
            }
            
            let audioBitrateDouble = Double(targetAudioBitrate)
            let availableVideoBitrate = max(120_000.0, (targetTotalBits / totalDurationSeconds) - audioBitrateDouble)
            
            // Intelligently scale resolution to prevent blockiness at lower bitrates (unless user locked original resolution)
            let maxDimForBitrate: Double
            if config.preserveResolutionInTargetMode {
                maxDimForBitrate = sourceLongEdge // Keep 100% full original resolution
            } else if availableVideoBitrate >= 5_000_000 {
                maxDimForBitrate = 3840.0 // 4K
            } else if availableVideoBitrate >= 2_200_000 {
                maxDimForBitrate = 1920.0 // 1080p
            } else if availableVideoBitrate >= 900_000 {
                maxDimForBitrate = 1280.0 // 720p
            } else if availableVideoBitrate >= 350_000 {
                maxDimForBitrate = 854.0  // 480p
            } else if availableVideoBitrate >= 180_000 {
                maxDimForBitrate = 640.0  // 360p
            } else {
                maxDimForBitrate = 480.0  // 240p
            }
            
            var autoScale = min(1.0, maxDimForBitrate / sourceLongEdge)
            if !config.preserveResolutionInTargetMode {
                let manualScale = min(max(config.videoResolutionScale, 0.25), 1.0)
                autoScale = min(autoScale, manualScale)
            } else {
                autoScale = 1.0
            }
            
            renderWidth = max(2, Int(Double(sourceWidth) * autoScale) & ~1)
            renderHeight = max(2, Int(Double(sourceHeight) * autoScale) & ~1)
            
            targetBitrate = Int(min(availableVideoBitrate, sourceBitrate * 0.95))
        } else {
            // Manual Quality Mode
            targetAudioBitrate = config.audioBitrate.bitrateInBps
            let resScale = min(max(config.videoResolutionScale, 0.25), 1.0)
            renderWidth = resScale < 0.999 ? Int(Double(sourceWidth) * resScale) : sourceWidth
            renderHeight = resScale < 0.999 ? Int(Double(sourceHeight) * resScale) : sourceHeight
            renderWidth = max(2, renderWidth & ~1)
            renderHeight = max(2, renderHeight & ~1)
            
            targetBitrate = calculateTargetBitrate(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                renderWidth: renderWidth,
                renderHeight: renderHeight,
                fps: frameRate,
                quality: config.videoQuality,
                codec: videoCodec,
                sourceBitrate: sourceBitrate
            )
        }
        
        progressHandler?(0.05)
        
        // ---- Setup Reader ----
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoCompressorError.cannotCreateReader
        }
        
        // Video reader output — decompress via Apple Silicon hardware decoder
        let readerVideoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        let readerVideoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerVideoOutputSettings)
        readerVideoOutput.alwaysCopiesSampleData = false
        
        guard reader.canAdd(readerVideoOutput) else {
            throw VideoCompressorError.cannotCreateReader
        }
        reader.add(readerVideoOutput)
        
        // Audio reader output (if present)
        let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
        var readerAudioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks?.first, !config.videoRemoveAudio {
            let audioOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [AVFormatIDKey: Int(kAudioFormatLinearPCM)]
            )
            audioOutput.alwaysCopiesSampleData = false
            if reader.canAdd(audioOutput) {
                reader.add(audioOutput)
                readerAudioOutput = audioOutput
            }
        }
        
        // ---- Setup Writer ----
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        } catch {
            throw VideoCompressorError.cannotCreateWriter
        }
        
        // Codec profile
        let profileLevel: String
        if videoCodec == .hevc {
            profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel as String
        } else {
            profileLevel = AVVideoProfileLevelH264HighAutoLevel
        }
        
        // VideoToolbox compression properties targeting Apple Silicon hardware encoder
        let compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: profileLevel,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: Int(frameRate * 2),  // 2-second keyframe GOP
            AVVideoAllowFrameReorderingKey: true
        ]
        
        let writerVideoInputSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: renderWidth,
            AVVideoHeightKey: renderHeight,
            AVVideoCompressionPropertiesKey: compressionProps
        ]
        
        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerVideoInputSettings)
        writerVideoInput.expectsMediaDataInRealTime = false
        let orientation = CGAffineTransform(a: preferredTransform.a, b: preferredTransform.b,
                                            c: preferredTransform.c, d: preferredTransform.d, tx: 0, ty: 0)
        let outputBounds = CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight).applying(orientation)
        writerVideoInput.transform = orientation.concatenating(
            CGAffineTransform(translationX: -outputBounds.minX, y: -outputBounds.minY)
        )
        
        guard writer.canAdd(writerVideoInput) else {
            throw VideoCompressorError.cannotCreateWriter
        }
        writer.add(writerVideoInput)
        
        // Audio writer input (AAC transcode via hardware)
        var writerAudioInput: AVAssetWriterInput?
        if readerAudioOutput != nil && targetAudioBitrate > 0 {
            let audioCompressionSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVNumberOfChannelsKey: targetAudioBitrate <= 48_000 ? 1 : 2, // Mono for super small sizes like 48k
                AVSampleRateKey: targetAudioBitrate <= 48_000 ? 32000.0 : 44100.0,
                AVEncoderBitRateKey: targetAudioBitrate
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioCompressionSettings)
            audioInput.expectsMediaDataInRealTime = false
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                writerAudioInput = audioInput
            }
        }
        
        // ---- Start encoding pipeline ----
        guard writer.startWriting() else {
            throw VideoCompressorError.encodingFailed(writer.error?.localizedDescription ?? "Start writing error")
        }
        guard reader.startReading() else {
            throw VideoCompressorError.encodingFailed(reader.error?.localizedDescription ?? "Start reading error")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        let context = VideoEncodingContext(
            reader: reader,
            writer: writer,
            readerVideoOutput: readerVideoOutput,
            writerVideoInput: writerVideoInput,
            readerAudioOutput: readerAudioOutput,
            writerAudioInput: writerAudioInput,
            targetFPS: config.videoFramerate.targetFPS,
            sourceFPS: sourceFPS,
            totalDurationSeconds: totalDurationSeconds,
            control: control,
            progressHandler: progressHandler
        )
        
        try await context.execute()
    }
    
    // ==========================================================================
    // MARK: - BITRATE CALCULATION (Source-Aware)
    // ==========================================================================
    
    /// Computes target bitrate that is ALWAYS less than the source.
    ///
    /// Strategy:
    /// 1. Start from the source bitrate and apply a reduction ratio based on
    ///    the quality slider.
    /// 2. Account for pixel count change when resolution is scaled down.
    /// 3. Account for codec efficiency (HEVC ≈ 40% more efficient than H.264).
    /// 4. Never exceed source bitrate. Never go below 200 kbps.
    private func calculateTargetBitrate(
        sourceWidth: Int,
        sourceHeight: Int,
        renderWidth: Int,
        renderHeight: Int,
        fps: Double,
        quality: Double,
        codec: AVVideoCodecType,
        sourceBitrate: Double
    ) -> Int {
        // Quality → bitrate ratio mapping:
        //   quality 0.30 (Max Compression) → keep 15% of source bitrate
        //   quality 0.50                   → keep 30% of source bitrate
        //   quality 0.75 (Balanced)        → keep 55% of source bitrate
        //   quality 0.90 (Vis. Lossless)   → keep 80% of source bitrate
        //   quality 1.00                   → keep 90% of source bitrate
        let bitrateRatio = 0.10 + (quality * 0.80)  // 0.10 … 0.90
        
        // Resolution scaling factor (pixel count ratio)
        let sourcePixels = Double(sourceWidth * sourceHeight)
        let renderPixels = Double(renderWidth * renderHeight)
        let resolutionRatio = sourcePixels > 0 ? (renderPixels / sourcePixels) : 1.0
        
        // Codec efficiency bonus (HEVC typically 30-40% more efficient)
        let codecEfficiency: Double = (codec == .hevc) ? 0.70 : 1.0
        
        // Final target
        var target = sourceBitrate * bitrateRatio * resolutionRatio * codecEfficiency
        
        // Hard cap: never exceed 90% of source bitrate (guarantee smaller file)
        let maxAllowed = sourceBitrate * 0.90
        target = min(target, maxAllowed)
        
        // Floor: minimum 200 kbps for any video
        target = max(target, 200_000)
        
        return Int(target)
    }
    
    // ==========================================================================
    // MARK: - ANIMATED GIF CONVERTER (Hardware-Accelerated Extraction)
    // ==========================================================================
    private func convertVideoToAnimatedGIF(
        asset: AVURLAsset,
        duration: CMTime,
        videoTrack: AVAssetTrack,
        destinationURL: URL,
        config: CompressionConfiguration,
        control: JobControl?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        let totalDurationSeconds = CMTimeGetSeconds(duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let sourceFPS = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30.0
        
        let displayBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let srcW = displayBounds.width
        let srcH = displayBounds.height
        
        // Target framerate
        let targetFPS: Double
        if let maxFPS = config.gifFramerate.maxFPS {
            targetFPS = min(sourceFPS, maxFPS)
        } else {
            targetFPS = sourceFPS
        }
        
        let frameInterval = 1.0 / max(targetFPS, 1.0)
        let frameStep = max(1, Int((sourceFPS / targetFPS).rounded()))
        
        // Adaptive resolution for GIF (keep dimensions compact to avoid huge files)
        let manualScale = min(max(config.videoResolutionScale, 0.20), 1.0)
        let maxAllowedDim: CGFloat = 640.0 * manualScale
        let longEdge = max(srcW, srcH)
        let scale = min(1.0, maxAllowedDim / longEdge)
        let dstW = max(1, Int((srcW * scale).rounded()))
        let dstH = max(1, Int((srcH * scale).rounded()))
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)
        ]
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        layer.setTransform(
            preferredTransform
                .concatenating(CGAffineTransform(translationX: -displayBounds.minX, y: -displayBounds.minY))
                .concatenating(CGAffineTransform(scaleX: CGFloat(dstW) / srcW, y: CGFloat(dstH) / srcH)),
            at: .zero
        )
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: duration)
        ))
        let composition = AVVideoComposition(configuration: .init(
            frameDuration: CMTime(seconds: 1.0 / sourceFPS, preferredTimescale: 600),
            instructions: [instruction], renderSize: CGSize(width: dstW, height: dstH)
        ))

        // GIF has no track transform: rotate the pixels before encoding, rather than stretching raw frames.
        let trackOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: outputSettings)
        trackOutput.videoComposition = composition
        trackOutput.alwaysCopiesSampleData = false
        
        guard reader.canAdd(trackOutput) else {
            throw VideoCompressorError.cannotCreateReader
        }
        reader.add(trackOutput)
        
        guard reader.startReading() else {
            throw VideoCompressorError.encodingFailed("Failed to start reading frames for GIF")
        }
        
        let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.gif.identifier as CFString,
            0,
            nil
        ) else {
            throw VideoCompressorError.cannotCreateWriter
        }
        
        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProps as CFDictionary)
        
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameInterval,
                kCGImagePropertyGIFUnclampedDelayTime: frameInterval
            ]
        ]
        
        var frameIndex = 0
        var addedCount = 0
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let control {
                while control.isPaused && !control.isCancelled {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if control.isCancelled {
                    reader.cancelReading()
                    throw VideoCompressorError.cancelled
                }
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let currentSec = CMTimeGetSeconds(timestamp)
            if totalDurationSeconds > 0 {
                let prog = min(0.92, max(0.05, currentSec / totalDurationSeconds))
                progressHandler?(prog)
            }
            
            if frameIndex % frameStep == 0 {
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
                    let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
                    let width = CVPixelBufferGetWidth(imageBuffer)
                    let height = CVPixelBufferGetHeight(imageBuffer)
                    
                    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                    if let context = CGContext(
                        data: baseAddress,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow,
                        space: colorSpace,
                        bitmapInfo: bitmapInfo
                    ), let cgImage = context.makeImage() {
                        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
                        
                        CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
                        addedCount += 1
                    } else {
                        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
                    }
                }
            }
            frameIndex += 1
        }
        
        guard addedCount > 0 else {
            throw VideoCompressorError.encodingFailed("No frames extracted from video")
        }
        
        progressHandler?(0.95)
        guard CGImageDestinationFinalize(destination) else {
            throw VideoCompressorError.encodingFailed("Failed to finalize animated GIF")
        }
        
        let finalData = mutableData as Data
        try finalData.write(to: destinationURL, options: .atomic)
        progressHandler?(1.0)
    }
    
    public func outputExtension(for sourceURL: URL, config: CompressionConfiguration) -> String {
        if config.videoCodec == .gif {
            return "gif"
        }
        return "mp4"
    }
}

// ==========================================================================
// MARK: - VIDEO ENCODING WORKER CONTEXT
// ==========================================================================

private final class VideoEncodingContext: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let readerVideoOutput: AVAssetReaderTrackOutput
    private let writerVideoInput: AVAssetWriterInput
    private let readerAudioOutput: AVAssetReaderTrackOutput?
    private let writerAudioInput: AVAssetWriterInput?
    private let targetFPS: Double?
    private let sourceFPS: Double
    private let totalDurationSeconds: Double
    private let control: JobControl?
    private let progressHandler: (@Sendable (Double) -> Void)?
    
    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        readerVideoOutput: AVAssetReaderTrackOutput,
        writerVideoInput: AVAssetWriterInput,
        readerAudioOutput: AVAssetReaderTrackOutput?,
        writerAudioInput: AVAssetWriterInput?,
        targetFPS: Double?,
        sourceFPS: Double,
        totalDurationSeconds: Double,
        control: JobControl?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) {
        self.reader = reader
        self.writer = writer
        self.control = control
        self.readerVideoOutput = readerVideoOutput
        self.writerVideoInput = writerVideoInput
        self.readerAudioOutput = readerAudioOutput
        self.writerAudioInput = writerAudioInput
        self.targetFPS = targetFPS
        self.sourceFPS = sourceFPS
        self.totalDurationSeconds = totalDurationSeconds
        self.progressHandler = progressHandler
    }
    
    func execute() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let videoQueue = DispatchQueue(label: "com.squeezebar.video.encode", qos: .userInitiated)
            let audioQueue = DispatchQueue(label: "com.squeezebar.audio.encode", qos: .userInitiated)
            let group = DispatchGroup()
            
            var hasFailed = false
            var failureError: Error?
            
            // Frame rate cadence filter
            let minFrameDeltaSec: Double = {
                if let target = self.targetFPS, target > 0, target < self.sourceFPS {
                    return (1.0 / target) * 0.90 // 10% threshold to avoid skipping boundary frames
                }
                return 0.0
            }()
            var lastAppendedTimeSec: Double = -1.0
            
            // Video encoding loop
            group.enter()
            self.writerVideoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
                guard let self = self else { return }
                while self.writerVideoInput.isReadyForMoreMediaData {
                    if let control = self.control, !control.checkpoint() {
                        self.writerVideoInput.markAsFinished()
                        if !hasFailed {
                            hasFailed = true
                            failureError = HardwareVideoCompressor.VideoCompressorError.cancelled
                        }
                        group.leave()
                        return
                    }
                    if let sampleBuffer = self.readerVideoOutput.copyNextSampleBuffer() {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let currentSec = CMTimeGetSeconds(timestamp)
                        if self.totalDurationSeconds > 0 {
                            let prog = min(0.95, max(0.05, currentSec / self.totalDurationSeconds))
                            self.progressHandler?(prog)
                        }
                        
                        // If target FPS is lower than source FPS, drop excess frames
                        if minFrameDeltaSec > 0 && lastAppendedTimeSec >= 0 {
                            if (currentSec - lastAppendedTimeSec) < minFrameDeltaSec {
                                // Skip/drop this frame to downsample framerate
                                continue
                            }
                        }
                        lastAppendedTimeSec = currentSec
                        
                        if !self.writerVideoInput.append(sampleBuffer) {
                            self.writerVideoInput.markAsFinished()
                            if !hasFailed {
                                hasFailed = true
                                failureError = self.writer.error ?? HardwareVideoCompressor.VideoCompressorError.encodingFailed("Failed appending video buffer")
                            }
                            group.leave()
                            return
                        }
                    } else {
                        self.writerVideoInput.markAsFinished()
                        if self.reader.status == .failed && !hasFailed {
                            hasFailed = true
                            failureError = self.reader.error ?? HardwareVideoCompressor.VideoCompressorError.encodingFailed("Reader failed during video processing")
                        }
                        group.leave()
                        return
                    }
                }
            }
            
            // Audio encoding loop (if present)
            if self.writerAudioInput != nil && self.readerAudioOutput != nil {
                group.enter()
                self.writerAudioInput?.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                    guard let self = self, let wInput = self.writerAudioInput, let rOutput = self.readerAudioOutput else { return }
                    while wInput.isReadyForMoreMediaData {
                        if let control = self.control, !control.checkpoint() {
                            wInput.markAsFinished()
                            if !hasFailed {
                                hasFailed = true
                                failureError = HardwareVideoCompressor.VideoCompressorError.cancelled
                            }
                            group.leave()
                            return
                        }
                        if let sampleBuffer = rOutput.copyNextSampleBuffer() {
                            if !wInput.append(sampleBuffer) {
                                wInput.markAsFinished()
                                group.leave()
                                return
                            }
                        } else {
                            wInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }
            
            group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
                guard let self = self else { return }
                if hasFailed {
                    self.reader.cancelReading()
                    self.writer.cancelWriting()
                    continuation.resume(throwing: failureError ?? HardwareVideoCompressor.VideoCompressorError.encodingFailed("Unknown failure"))
                    return
                }
                
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        self.progressHandler?(1.0)
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: self.writer.error ?? HardwareVideoCompressor.VideoCompressorError.encodingFailed("Failed to finalize video"))
                    }
                }
            }
        }
    }
}
