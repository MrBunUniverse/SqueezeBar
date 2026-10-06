import SwiftUI

public struct QueueItemSettingsSheet: View {
    @ObservedObject var item: StagedQueueItem
    @ObservedObject private var state = AppState.shared
    @Environment(\.presentationMode) var presentationMode
    
    public init(item: StagedQueueItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: iconForMediaType(item.mediaType))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(state.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack(spacing: 6) {
                        Text(item.formattedOriginalSize)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        Text(item.formatExtension)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(state.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(state.accentColor.opacity(0.12)))
                    }
                }
                
                Spacer()
                
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(state.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.03))
            
            Divider()
                .opacity(0.15)
            
            // Settings Form Body
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // MARK: - Quality Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Quality")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(item.customQuality * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(state.accentColor)
                        }
                        
                        LiquidGlassSlider(
                            value: $item.customQuality,
                            range: 0.10...1.0,
                            step: 0.05,
                            accentColor: state.accentColor
                        )
                        .accessibilityLabel("Quality")
                    }
                    
                    // MARK: - Resolution Scale (Images & Videos)
                    if item.mediaType == .image || item.mediaType == .video {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Resolution Scale")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 6) {
                                scaleButton(title: "100%", value: 1.0)
                                scaleButton(title: "75%", value: 0.75)
                                scaleButton(title: "50%", value: 0.50)
                                scaleButton(title: "25%", value: 0.25)
                            }
                        }
                    }
                    
                    // MARK: - Target Size Limit
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target Size Limit")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 6) {
                            targetSizeButton(title: "Off", mode: .off)
                            targetSizeButton(title: "25MB", mode: .discord25)
                            targetSizeButton(title: "10MB", mode: .email10)
                            targetSizeButton(title: "50MB", mode: .discord50)
                        }
                    }
                    
                    // MARK: - Format-Specific Controls
                    if item.mediaType == .image {
                        imageFormatSection
                    } else if item.mediaType == .video {
                        videoCodecSection
                    } else if item.mediaType == .audio {
                        audioBitrateSection
                    } else if item.mediaType == .pdf {
                        pdfControlsSection
                    }
                    
                    // MARK: - Metadata Privacy
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Strip EXIF & Metadata")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text("Remove GPS, camera, and author metadata")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $item.stripMetadata)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: state.accentColor))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 380)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12).opacity(0.98))
        )
        .font(.system(.body, design: .rounded))
    }
    
    // MARK: - Image Format Picker
    private var imageFormatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output Format")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            Picker("", selection: $item.customImageFormat) {
                Text("Preserve Original").tag(ImageFormatPolicy.preserveOriginal)
                Text("Modern WebP").tag(ImageFormatPolicy.webpModern)
                Text("Modern HEIC").tag(ImageFormatPolicy.heicModern)
                Text("Modern AVIF").tag(ImageFormatPolicy.avifModern)
                Text("PNG").tag(ImageFormatPolicy.pngLossless)
                Text("Web JPEG").tag(ImageFormatPolicy.jpegStandard)
            }
            .pickerStyle(.menu)
        }
    }
    
    // MARK: - Video Codec Picker
    private var videoCodecSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Codec")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Picker("", selection: $item.customVideoCodec) {
                    Text("HEVC (H.265)").tag(VideoCodecPreference.hevc)
                    Text("H.264 Universal").tag(VideoCodecPreference.h264)
                    Text("Animated GIF").tag(VideoCodecPreference.gif)
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("Remove Audio Track")
                    .font(.system(size: 11, design: .rounded))
                Spacer()
                Toggle("", isOn: $item.customVideoRemoveAudio)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: state.accentColor))
            }
        }
    }
    
    // MARK: - Audio Bitrate Picker
    private var audioBitrateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio Bitrate")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Picker("", selection: $item.customAudioBitrate) {
                Text("320 kbps (Studio)").tag(AudioBitratePreference.k320)
                Text("256 kbps (High)").tag(AudioBitratePreference.k256)
                Text("192 kbps (Quality)").tag(AudioBitratePreference.k192)
                Text("128 kbps (Standard)").tag(AudioBitratePreference.k128)
                Text("64 kbps (Compact)").tag(AudioBitratePreference.k64)
            }
            .pickerStyle(.menu)
        }
    }
    
    // MARK: - PDF Controls
    private var pdfControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PDF Render DPI")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Picker("", selection: $item.customPDFDPI) {
                    Text("300 DPI (Print)").tag(PDFDPIOption.dpi300)
                    Text("200 DPI (High)").tag(PDFDPIOption.dpi200)
                    Text("150 DPI (Balanced)").tag(PDFDPIOption.dpi150)
                    Text("72 DPI (Screen)").tag(PDFDPIOption.dpi72)
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("Convert to Grayscale")
                    .font(.system(size: 11, design: .rounded))
                Spacer()
                Toggle("", isOn: $item.customPDFGrayscale)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: state.accentColor))
            }
        }
    }
    
    private func scaleButton(title: LocalizedStringKey, value: Double) -> some View {
        let isSelected = abs(item.customResolutionScale - value) < 0.01
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                item.customResolutionScale = value
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? state.accentColor : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? state.accentColor : Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func targetSizeButton(title: LocalizedStringKey, mode: TargetSizeMode) -> some View {
        let isSelected = (item.customTargetSizeMode == mode)
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                item.customTargetSizeMode = mode
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? state.accentColor : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? state.accentColor : Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func iconForMediaType(_ type: MediaType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.text.fill"
        case .unsupported: return "doc"
        }
    }
}
