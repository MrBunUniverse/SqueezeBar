import Foundation
import AVFoundation
import CoreMedia

public struct HardwareAudioCompressor: Sendable {
    
    public enum AudioCompressorError: LocalizedError {
        case unreadableSource
        case noAudioTrackFound
        case cannotCreateReader
        case cannotCreateWriter
        case encodingFailed(String)
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .unreadableSource: return String(localized: "Unable to open or read audio source file")
            case .noAudioTrackFound: return String(localized: "No audio track found in file")
            case .cannotCreateReader: return String(localized: "Failed to initialize AVAssetReader for audio")
            case .cannotCreateWriter: return String(localized: "Failed to initialize AVAssetWriter for audio")
            case .encodingFailed(let msg): return String(localized: "Audio compression failed: \(msg)")
            case .cancelled: return String(localized: "Audio compression cancelled")
            }
        }
    }
    
    public init() {}
    
    // ==========================================================================
    // MARK: - PUBLIC API
    // ==========================================================================
    
    /// Hardware-accelerated audio compression into high-efficiency MPEG-4 AAC (.m4a).
    public func compressAudio(
        from sourceURL: URL,
        to destinationURL: URL,
        config: CompressionConfiguration,
        control: JobControl? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Ensure destination does not exist
        try? FileManager.default.removeItem(at: destinationURL)
        
        let asset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration)
        } catch {
            throw AudioCompressorError.unreadableSource
        }
        
        guard let audioTrack = tracks.first else {
            throw AudioCompressorError.noAudioTrackFound
        }
        
        let totalDurationSeconds = CMTimeGetSeconds(duration)
        guard totalDurationSeconds > 0 else {
            throw AudioCompressorError.unreadableSource
        }
        
        progressHandler?(0.05)
        
        // ---- Bitrate Calculation (Target Size or Manual) ----
        let targetBitrate: Int
        if let targetMB = config.effectiveTargetSizeMB {
            // Target file size automated mode
            let targetBytes = targetMB * 1024.0 * 1024.0 * 0.95
            let calculatedBitrate = (targetBytes * 8.0) / totalDurationSeconds
            targetBitrate = max(32_000, min(320_000, Int(calculatedBitrate)))
        } else {
            targetBitrate = config.audioBitrate.bitrateInBps
        }
        
        // ---- Setup Reader ----
        let reader = try AVAssetReader(asset: asset)
        let readerAudioOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        readerAudioOutput.alwaysCopiesSampleData = false
        
        guard reader.canAdd(readerAudioOutput) else {
            throw AudioCompressorError.cannotCreateReader
        }
        reader.add(readerAudioOutput)
        
        // ---- Setup Writer ----
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .m4a)
        
        let numberOfChannels: Int = targetBitrate <= 32_000 ? 1 : 2
        let sampleRate: Double = targetBitrate <= 16_000 ? 16000.0 : (targetBitrate <= 32_000 ? 22050.0 : 44100.0)
        
        let audioCompressionSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: numberOfChannels,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: targetBitrate
        ]
        
        let writerAudioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioCompressionSettings
        )
        writerAudioInput.expectsMediaDataInRealTime = false
        
        guard writer.canAdd(writerAudioInput) else {
            throw AudioCompressorError.cannotCreateWriter
        }
        writer.add(writerAudioInput)
        
        // ---- Begin Encoding ----
        guard reader.startReading() else {
            throw AudioCompressorError.encodingFailed("Failed to start audio reader")
        }
        guard writer.startWriting() else {
            throw AudioCompressorError.encodingFailed("Failed to start audio writer")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        let context = AudioEncodingContext(
            reader: reader,
            writer: writer,
            readerOutput: readerAudioOutput,
            writerInput: writerAudioInput,
            totalDurationSeconds: totalDurationSeconds,
            control: control,
            progressHandler: progressHandler
        )
        
        try await context.encode()
        progressHandler?(1.0)
    }
    
    public func outputExtension(for sourceURL: URL, config: CompressionConfiguration) -> String {
        return "m4a"
    }
}

// ==========================================================================
// MARK: - AUDIO ENCODING WORKER CONTEXT
// ==========================================================================

private final class AudioEncodingContext: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let readerOutput: AVAssetReaderTrackOutput
    private let writerInput: AVAssetWriterInput
    private let totalDurationSeconds: Double
    private let control: JobControl?
    private let progressHandler: (@Sendable (Double) -> Void)?
    
    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        readerOutput: AVAssetReaderTrackOutput,
        writerInput: AVAssetWriterInput,
        totalDurationSeconds: Double,
        control: JobControl?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) {
        self.control = control
        self.reader = reader
        self.writer = writer
        self.readerOutput = readerOutput
        self.writerInput = writerInput
        self.totalDurationSeconds = totalDurationSeconds
        self.progressHandler = progressHandler
    }
    
    func encode() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.squeezebar.audio.compressor.queue", qos: .userInitiated)
            
            self.writerInput.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard let self = self else { return }
                
                while self.writerInput.isReadyForMoreMediaData {
                    if let control = self.control, !control.checkpoint() {
                        self.writerInput.markAsFinished()
                        self.reader.cancelReading()
                        self.writer.cancelWriting()
                        continuation.resume(throwing: HardwareAudioCompressor.AudioCompressorError.cancelled)
                        return
                    }
                    if let sampleBuffer = self.readerOutput.copyNextSampleBuffer() {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let currentSec = CMTimeGetSeconds(timestamp)
                        if self.totalDurationSeconds > 0 {
                            let prog = min(0.95, max(0.05, currentSec / self.totalDurationSeconds))
                            self.progressHandler?(prog)
                        }
                        
                        if !self.writerInput.append(sampleBuffer) {
                            self.writerInput.markAsFinished()
                            continuation.resume(throwing: HardwareAudioCompressor.AudioCompressorError.encodingFailed("Failed to append audio sample buffer"))
                            return
                        }
                    } else {
                        // Finished reading
                        self.writerInput.markAsFinished()
                        
                        self.writer.finishWriting {
                            if self.writer.status == .completed {
                                continuation.resume(returning: ())
                            } else if let error = self.writer.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(throwing: HardwareAudioCompressor.AudioCompressorError.encodingFailed("Unknown writer termination"))
                            }
                        }
                        return
                    }
                }
            }
        }
    }
}
